require "faraday"
require "mcp"

module Higgsfield
  module Mcp
    # One authenticated conversation with the Higgsfield MCP server. The app is
    # a plain MCP client: it calls tools directly, no language model involved.
    #
    #   session = Higgsfield::Mcp::Session.new
    #   session.call("balance") # => { "credits" => 2950.5, ... }
    class Session
      SCOPE = "openid email offline_access".freeze
      EXPIRED = "A conexão com a Higgsfield expirou. Clique em “Conectar Higgsfield” de novo.".freeze

      # Raised by the provider when a background job would need a browser login.
      class LoginRequired < StandardError; end

      def self.config
        Higgsfield.config[:mcp]
      end

      def initialize(connection: HiggsfieldConnection.current, config: self.class.config)
        @connection = connection
        @config = config
      end

      def connected?
        @connection.connected?
      end

      # Starts the browser login. Returns the Higgsfield authorization URL.
      def authorization_url
        flow = ::MCP::Client::OAuth::Flow.new(provider: provider(interactive: true))
        flow.run!(server_url: server_url, scope: SCOPE)
        flow.authorization_url.to_s
      end

      # Completes the login with the query params of the redirect back to us.
      def finish_login(callback_params)
        ::MCP::Client::OAuth::Flow.new(provider: provider(interactive: true))
          .finish!(server_url: server_url, callback_params: callback_params.to_h.stringify_keys)
      end

      # Calls a tool and returns its JSON result as a Hash (or the raw text).
      def call(tool, arguments = {})
        raise ConfigurationError, "Conecte a Higgsfield no topo da página para gerar imagens e vídeos." unless connected?

        renewed = false
        begin
          if @connection.access_token_expired?
            renew_access_token!
            renewed = true
          end
          call_tool(tool, arguments)
        rescue LoginRequired
          # The server refused the token and the gem could not renew it on its
          # own. It swallows the reason, so renew here, where the reason is
          # known, and try once more.
          @connection.discard_pending_authorizations!
          raise ConfigurationError, EXPIRED unless @connection.refresh_token
          raise RequestError, "A Higgsfield recusou o acesso mesmo com o token renovado." if renewed

          close_client
          renew_access_token!
          renewed = true
          retry
        end
      end

      # Swaps the refresh token for a new access token. Throws the login away
      # only when the authorization server says it is dead; anything else
      # keeps it for the next attempt.
      def renew_access_token!
        @connection.reload # another process may have renewed (and rotated) it already
        refresh_token = @connection.refresh_token
        unless refresh_token
          @connection.disconnect! # an expired access token alone cannot be renewed
          raise ConfigurationError, EXPIRED
        end

        ::MCP::Client::OAuth::Flow.new(provider: provider(interactive: false)).refresh!(server_url: server_url)
      rescue ::MCP::Client::OAuth::Flow::AuthorizationError => e
        Rails.logger.warn("[repo2ad] higgsfield token refresh failed: #{e.class}: #{e.message}")
        @connection.reload
        return if @connection.refresh_token != refresh_token && !@connection.access_token_expired? # lost a race, the winner's tokens are good

        if login_lost?(e)
          @connection.disconnect!
          raise ConfigurationError, "#{EXPIRED} (#{e.message.truncate(200)})"
        end
        raise TransientError, "Não foi possível renovar o acesso à Higgsfield agora: #{e.message.truncate(200)}"
      end

      private

      # Errors no retry can fix: the refresh token was revoked or expired
      # (invalid_grant), the client registration is gone (invalid_client), or
      # the server now names another authorization server (SEP-2352 refuses to
      # present the tokens to it). Network, 5xx, 429 and discovery hiccups are
      # transient.
      def login_lost?(error)
        return true if error.is_a?(::MCP::Client::OAuth::Flow::InvalidGrantError)
        return true if error.error.in?(%w[invalid_client unauthorized_client])

        error.message.match?(/different authorization server|re-authorization is required|re-registration is required|no client_information/)
      end

      def call_tool(tool, arguments)
        response = client.call_tool(name: tool, arguments: arguments)
        result = response.is_a?(Hash) && response.key?("result") ? response["result"] : response
        text = Array(result&.dig("content")).filter_map { it["text"] if it["type"] == "text" }.join("\n")
        payload = result&.dig("structuredContent") || parse(text)

        raise RequestError.new("Higgsfield (#{tool}): #{text.presence || "erro desconhecido"}".truncate(500), body: text) if result&.dig("isError")
        payload
      rescue ::MCP::Client::ServerError, ::MCP::Client::RequestHandlerError => e
        raise TransientError, "Higgsfield MCP: #{e.message}" if transient?(e)
        raise RequestError, "Higgsfield MCP: #{e.message}"
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::ServerError => e
        raise TransientError, "Falha de rede ao falar com a Higgsfield: #{e.message}"
      ensure
        close_client
      end

      def close_client
        @client&.close rescue nil # rubocop:disable Style/RescueModifier
        @client = nil
      end

      def server_url = @config[:url]

      def client
        @client ||= begin
          transport = ::MCP::Client::HTTP.new(url: server_url, oauth: provider(interactive: false))
          ::MCP::Client.new(transport: transport).tap do |mcp|
            mcp.connect(client_info: { name: "repo2ad", version: "0.1.0" })
          end
        end
      end

      # interactive: the browser is there to follow the redirect (connect action).
      # Otherwise (jobs) a needed login is an error the UI must surface.
      def provider(interactive:)
        ::MCP::Client::OAuth::Provider.new(
          client_metadata: {
            client_name: "Repo2Ad",
            redirect_uris: [ @config[:redirect_uri] ],
            grant_types: %w[authorization_code refresh_token],
            response_types: %w[code],
            token_endpoint_auth_method: "none"
          },
          redirect_uri: @config[:redirect_uri],
          scope: SCOPE,
          storage: @connection,
          redirect_handler: interactive ? ->(_url) { } : ->(_url) { raise LoginRequired }
        )
      end

      def parse(text)
        JSON.parse(text)
      rescue JSON::ParserError
        text
      end

      def transient?(error)
        error.message.match?(/timeout|temporar|unavailable|rate limit|429|5\d\d/i)
      end
    end
  end
end
