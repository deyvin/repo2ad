require "json"
require "open3"

module Media
  # Mede imagem ou vídeo com ffprobe: largura, altura, duração (s, nil para imagem) e aspecto.
  # Imagem precisa ser medida depois do Media::Normalizer: o ffprobe não aplica o EXIF de orientação de JPEG.
  class Probe
    class Error < StandardError; end

    Result = Data.define(:width, :height, :duration, :aspect)

    # Rótulos do app. A razão largura/altura precisa ficar a até 2% do alvo.
    ASPECTS = {
      "9:16" => 9.0 / 16,
      "16:9" => 16.0 / 9,
      "4:5" => 4.0 / 5,
      "1:1" => 1.0,
      "3:4" => 3.0 / 4
    }.freeze
    TOLERANCE = 0.02

    IMAGE_CODECS = %w[mjpeg png webp gif bmp].freeze
    # image2 é o demuxer de imagem única (JPEG); *_pipe cobre png_pipe, webp_pipe, bmp_pipe etc.
    IMAGE_FORMAT = /\A(?:image2|image2pipe|\w+_pipe)\z/

    def self.call(path)
      new(path).call
    end

    def initialize(path)
      @path = path.to_s
    end

    def call
      data = run_ffprobe
      stream = data.fetch("streams", []).find { |s| s["codec_type"] == "video" }
      width, height = dimensions(stream)

      Result.new(
        width: width,
        height: height,
        duration: duration(stream, data),
        aspect: aspect_label(width, height)
      )
    end

    private

    def run_ffprobe
      out, _err, status = Open3.capture3(
        "ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", @path
      )
      raise Error, "arquivo inválido ou ilegível" unless status.success?

      JSON.parse(out)
    rescue Errno::ENOENT
      raise Error, "ffprobe não está instalado"
    rescue JSON::ParserError
      raise Error, "arquivo inválido ou ilegível"
    end

    # Vídeo girado (celular) guarda a rotação em metadados: largura e altura trocam de lugar.
    def dimensions(stream)
      raise Error, "o arquivo não tem imagem ou vídeo legível" if stream.nil? || stream["width"].to_i <= 0 || stream["height"].to_i <= 0

      width = stream["width"].to_i
      height = stream["height"].to_i
      rotation = rotation_degrees(stream)
      rotation % 180 == 90 ? [ height, width ] : [ width, height ]
    end

    def rotation_degrees(stream)
      from_tags = stream.dig("tags", "rotate")
      from_side_data = Array(stream["side_data_list"]).filter_map { |d| d["rotation"] }.first
      (from_tags || from_side_data || 0).to_i
    end

    # Só vídeo tem duração. Um JPEG aparece como vídeo de 1 quadro e o format_name traz uma duração falsa (0,04 s).
    def duration(stream, data)
      return nil if image?(stream, data)

      value = stream["duration"] || data.dig("format", "duration")
      Float(value, exception: false)
    end

    def image?(stream, data)
      return true if data.dig("format", "format_name").to_s.match?(IMAGE_FORMAT)

      IMAGE_CODECS.include?(stream["codec_name"]) && stream["nb_frames"].to_i <= 1
    end

    def aspect_label(width, height)
      ratio = width.to_f / height
      label = ASPECTS.find { |_name, target| ((ratio - target) / target).abs <= TOLERANCE }&.first
      label || format("%.2f", ratio)
    end
  end
end
