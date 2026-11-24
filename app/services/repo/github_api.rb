require "erb"
require "json"
require "net/http"
require "timeout"
require "uri"

module Repo
  # Cliente mínimo da API do GitHub com Net::HTTP. O token é opcional (GITHUB_TOKEN no ENV).
  class GithubApi
    HOST = "api.github.com".freeze
    # Redirecionamentos do tarball só seguem para estes hosts, e nunca levam o token.
    REDIRECT_HOSTS = %w[codeload.github.com github.com objects.githubusercontent.com].freeze
    MAX_REDIRECTS = 3
    TIMEOUT_SECONDS = 20
    # Espera máxima que o GitHub pode pedir. Acima disso, o retry usa o backoff do job.
    MAX_RETRY_AFTER = 15 * 60
    NOT_FOUND = "repositório não encontrado; só repositórios públicos são aceitos".freeze
    UNREACHABLE = "não consegui falar com o GitHub agora; tente de novo".freeze
    RATE_LIMITED = "limite de requisições do GitHub atingido; configure GITHUB_TOKEN".freeze

    def initialize(token: ENV["GITHUB_TOKEN"].presence)
      @token = token
    end

    def repository(owner:, name:)
      get_json("/repos/#{owner}/#{name}", not_found: NOT_FOUND)
    end

    def commit_sha(owner:, name:, branch:)
      path = "/repos/#{owner}/#{name}/commits/#{ERB::Util.url_encode(branch)}"
      get_json(path, not_found: "branch não encontrada: #{branch}").fetch("sha")
    end

    def download_tarball(owner:, name:, sha:, destination:, max_bytes:)
      uri = URI("https://#{HOST}/repos/#{owner}/#{name}/tarball/#{sha}")
      download(uri, destination: destination, max_bytes: max_bytes, auth: true, redirects_left: MAX_REDIRECTS)
    end

    private

    def get_json(path, not_found:)
      get_json_from(URI("https://#{HOST}#{path}"), not_found: not_found)
    end

    # Repositório renomeado responde 3xx apontando para a API nova. Só seguimos para api.github.com, até
    # MAX_REDIRECTS vezes; o token vai junto porque é o mesmo host.
    def get_json_from(uri, not_found:, redirects_left: MAX_REDIRECTS)
      response = request(uri, auth: true, accept: "application/vnd.github+json")
      if response.is_a?(Net::HTTPRedirection)
        raise Error, "redirecionamentos demais ao consultar o GitHub" if redirects_left.zero?

        return get_json_from(api_redirect_uri(response["location"]), not_found: not_found,
                                                                     redirects_left: redirects_left - 1)
      end

      check_status!(response, not_found: not_found)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise Error, "resposta inesperada do GitHub"
    end

    def api_redirect_uri(location)
      uri = URI.parse(location)
      raise Error, "redirecionamento inesperado do GitHub" unless uri.scheme == "https" && uri.host == HOST

      uri
    rescue URI::InvalidURIError
      raise Error, "redirecionamento inesperado do GitHub"
    end

    # Abre a conexão TLS com o host. Os testes trocam este método por um Net::HTTP de mentira.
    def connect(uri, &block)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                      open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS, &block)
    end

    def request(uri, auth:, accept: nil)
      connect(uri) do |http|
        http.request(build_request(uri, auth: auth, accept: accept))
      end
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise TransientError, UNREACHABLE
    end

    def download(uri, destination:, max_bytes:, auth:, redirects_left:)
      location = nil
      connect(uri) do |http|
        http.request(build_request(uri, auth: auth)) do |response|
          if response.is_a?(Net::HTTPRedirection)
            location = response["location"]
          else
            check_status!(response, not_found: NOT_FOUND)
            save_body(response, destination, max_bytes)
          end
        end
      end
      return destination unless location

      raise Error, "redirecionamentos demais ao baixar o repositório" if redirects_left.zero?

      download(redirect_uri(location), destination: destination, max_bytes: max_bytes,
                                       auth: false, redirects_left: redirects_left - 1)
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise TransientError, UNREACHABLE
    end

    def build_request(uri, auth:, accept: nil)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Repo2Ad"
      if accept
        request["Accept"] = accept
        request["X-GitHub-Api-Version"] = "2022-11-28"
      end
      request["Authorization"] = "Bearer #{@token}" if auth && @token
      request
    end

    def save_body(response, destination, max_bytes)
      too_big = "repositório acima do limite de #{max_bytes / 1024 / 1024} MB"
      raise Error, too_big if response["content-length"].to_i > max_bytes

      size = 0
      File.open(destination, "wb") do |file|
        response.read_body do |chunk|
          size += chunk.bytesize
          raise Error, too_big if size > max_bytes

          file.write(chunk)
        end
      end
    end

    def redirect_uri(location)
      uri = URI.parse(location)
      raise Error, "redirecionamento inesperado do GitHub" unless uri.scheme == "https" && REDIRECT_HOSTS.include?(uri.host)

      uri
    rescue URI::InvalidURIError
      raise Error, "redirecionamento inesperado do GitHub"
    end

    def check_status!(response, not_found:)
      code = response.code.to_i
      return if code.between?(200, 299)

      case code
      when 401 then raise Error, "token do GITHUB_TOKEN recusado pelo GitHub"
      when 403, 429
        if code == 429 || response["x-ratelimit-remaining"] == "0"
          raise TransientError.new(RATE_LIMITED, retry_after: retry_after(response))
        end

        raise Error, "o GitHub recusou o acesso (HTTP #{code})"
      when 404 then raise Error, not_found
      when 500..599 then raise TransientError, "o GitHub respondeu HTTP #{code}"
      else raise Error, "erro ao consultar o GitHub (HTTP #{code})"
      end
    end

    # Segundos até poder tentar de novo: Retry-After, ou X-RateLimit-Reset (epoch). Nil se não vier ou for longo demais.
    def retry_after(response)
      seconds =
        if response["retry-after"].to_s.match?(/\A\d+\z/)
          response["retry-after"].to_i
        elsif response["x-ratelimit-reset"].to_s.match?(/\A\d+\z/)
          response["x-ratelimit-reset"].to_i - Time.now.to_i
        end
      seconds if seconds&.positive? && seconds <= MAX_RETRY_AFTER
    end
  end
end
