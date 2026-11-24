require "securerandom"
require "tmpdir"
require "vips"

module Media
  # Deixa uma imagem pronta para os modelos e o compositor (§6.1, §7 regra 6):
  # HEIC vira JPEG, a rotação do EXIF é aplicada e o EXIF restante sai, o lado maior
  # fica no máximo em max_side (nunca aumenta). PNG continua PNG (screenshots e transparência).
  #
  #   path = Media::Normalizer.call("foto.heic", max_side: 1568)  # => ".../normalized-....jpg"
  #
  # O arquivo de saída é novo e fica em dest_dir (padrão: diretório temporário); quem chama
  # anexa ou move e apaga depois.
  class Normalizer
    class Error < StandardError; end

    DEFAULT_MAX_SIDE = 2048
    JPEG_QUALITY = 90

    def self.call(input_path, max_side: DEFAULT_MAX_SIDE, dest_dir: Dir.tmpdir)
      new(input_path, max_side:, dest_dir:).call
    end

    def initialize(input_path, max_side:, dest_dir:)
      @input_path = input_path.to_s
      @max_side = Integer(max_side)
      @dest_dir = dest_dir.to_s
      raise ArgumentError, "max_side precisa ser positivo" unless @max_side.positive?
    end

    def call
      raise Error, "arquivo não encontrado: #{File.basename(@input_path)}" unless File.file?(@input_path)

      loader = Vips.vips_foreign_find_load(@input_path)
      raise Error, "formato de imagem não suportado (use JPG, PNG ou HEIC)" if loader.nil?

      # thumbnail lê já reduzido, aplica a rotação do EXIF e converte para sRGB quando há perfil de cor.
      image = Vips::Image.thumbnail(@input_path, @max_side, height: @max_side, size: :down)
      image = image.colourspace(:srgb) unless image.interpretation == :srgb

      png = loader.start_with?("VipsForeignLoadPng") || image.has_alpha?
      output = File.join(@dest_dir, "normalized-#{SecureRandom.hex(8)}.#{png ? "png" : "jpg"}")

      if png
        image.pngsave(output, keep: :none)
      else
        image.jpegsave(output, Q: JPEG_QUALITY, keep: :none)
      end
      output
    rescue Vips::Error
      raise Error, "não foi possível ler a imagem #{File.basename(@input_path)}: arquivo inválido ou corrompido"
    end
  end
end
