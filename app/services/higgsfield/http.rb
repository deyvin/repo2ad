require "ipaddr"
require "net/http"
require "resolv"
require "tempfile"

module Higgsfield
  # HTTP fora do MCP: PUT do upload pré-assinado e download do resultado na CDN.
  # As URLs vêm da Higgsfield (dado externo): só https, e nunca para hosts internos (SSRF). O host é
  # resolvido uma vez, todos os endereços precisam ser públicos e a conexão vai para o IP verificado.
  class Http
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 120
    MAX_REDIRECTS = 3
    MAX_DOWNLOAD = 500.megabytes

    BLOCKED_NETWORKS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
      198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
    ].map { IPAddr.new(_1) }.freeze

    def initialize(resolver: Resolv)
      @resolver = resolver
    end

    def put(url, bytes, content_type)
      uri = https_uri(url)
      request = Net::HTTP::Put.new(uri)
      request["Content-Type"] = content_type
      request["If-None-Match"] = "*" # faz parte da assinatura pré-assinada
      request.body = bytes
      response = start(uri) { _1.request(request) }
      return if response.is_a?(Net::HTTPSuccess)

      raise error_for(response), "Falha ao enviar a mídia para a Higgsfield (HTTP #{response.code})"
    end

    # Baixa para um arquivo temporário (vídeos podem ser grandes). Quem chama fecha o io.
    def get(url, redirects: MAX_REDIRECTS)
      uri = https_uri(url)

      start(uri) do |http|
        http.request(Net::HTTP::Get.new(uri)) do |response|
          if response.is_a?(Net::HTTPRedirection) && redirects.positive?
            return get(URI.join(url, response["location"]).to_s, redirects: redirects - 1)
          end
          raise error_for(response), "Falha ao baixar o resultado da Higgsfield (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)

          return save(response, uri)
        end
      end
    end

    private

    def save(response, uri)
      file = Tempfile.new([ "higgsfield", File.extname(uri.path) ], binmode: true)
      size = 0
      response.read_body do |chunk|
        size += chunk.bytesize
        raise RequestError, "O resultado da Higgsfield passou de #{MAX_DOWNLOAD / 1.megabyte} MB" if size > MAX_DOWNLOAD

        file.write(chunk)
      end
      file.rewind
      content_type = response.content_type.presence || Marcel::MimeType.for(file, name: File.basename(uri.path))
      Gateway::Download.new(io: file, content_type: content_type, filename: File.basename(uri.path).presence || "resultado")
    rescue StandardError
      file&.close!
      raise
    end

    def https_uri(url)
      uri = URI(url.to_s)
      raise RequestError, "URL da Higgsfield recusada: só https é aceito" unless uri.is_a?(URI::HTTPS) && uri.host.present?

      uri
    rescue URI::InvalidURIError
      raise RequestError, "URL da Higgsfield inválida"
    end

    # Endereço público do host; IP literal, localhost ou nome que resolve para rede interna é recusado.
    def public_address(host)
      addresses = begin
        [ IPAddr.new(host.delete_prefix("[").delete_suffix("]")) ]
      rescue IPAddr::InvalidAddressError
        @resolver.getaddresses(host).map { IPAddr.new(_1) }
      end
      raise TransientError, "Não foi possível resolver o endereço #{host}" if addresses.empty?

      internal = addresses.find { |ip| internal?(ip) }
      raise RequestError, "URL da Higgsfield recusada: #{host} aponta para a rede interna" if internal

      addresses.first.to_s
    end

    def internal?(ip)
      ip = ip.native if ip.ipv6? && ip.ipv4_mapped?
      BLOCKED_NETWORKS.any? { |network| network.family == ip.family && network.include?(ip) }
    end

    def start(uri, &)
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = public_address(uri.host) # conecta no IP verificado; SNI e Host continuam com o nome
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.start(&)
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
      raise TransientError, "Falha de rede ao falar com a Higgsfield: #{e.class}"
    end

    def error_for(response)
      code = response.code.to_i
      code >= 500 || code == 429 ? TransientError : RequestError
    end
  end
end
