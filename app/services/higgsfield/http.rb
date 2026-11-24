require "net/http"
require "tempfile"

module Higgsfield
  # HTTP fora do MCP: PUT do upload pré-assinado e download do resultado na CDN.
  class Http
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 120
    MAX_REDIRECTS = 3
    MAX_DOWNLOAD = 500.megabytes

    def put(url, bytes, content_type)
      uri = URI(url)
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
      uri = URI(url)
      raise RequestError, "URL de resultado inválida" unless uri.is_a?(URI::HTTPS)

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

    def start(uri, &)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, &)
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
      raise TransientError, "Falha de rede ao falar com a Higgsfield: #{e.class}"
    end

    def error_for(response)
      code = response.code.to_i
      code >= 500 || code == 429 ? TransientError : RequestError
    end
  end
end
