module Frames
  # Executa o compose_plan do P4 (app/prompts/schemas/p4_spec.json, §6.4): screenshots e fotos reais
  # em molduras sobre a cor da marca, já no aspecto final do vídeo (D5, D6).
  #
  #   Frames::Composer.call(plan, media: { "docs/screenshots/galeria.png" => "/tmp/galeria.png" }, to: "start.png")
  #
  # Camadas, na ordem do plano (a primeira fica embaixo):
  # - x_pct, y_pct: canto superior esquerdo da moldura, em % da largura e da altura do canvas;
  # - width_pct: largura da moldura em % da largura do canvas (a altura segue a proporção da imagem);
  # - rotation_deg: graus no sentido horário, em volta do centro da moldura;
  # - crop_top_pct: % da altura da imagem que fica, a partir do topo (0 ou 100 = sem corte),
  #   ajustada para a linha em branco mais próxima.
  class Composer
    class Error < StandardError; end

    CANVASES = {
      "16:9" => [ 2752, 1536 ],
      "9:16" => [ 1536, 2752 ],
      "4:5" => [ 2048, 2560 ],
      "1:1" => [ 2048, 2048 ]
    }.freeze
    FRAMES = { "browser" => BrowserFrame, "print" => PrintFrame, "none" => NoFrame }.freeze
    MAX_LAYERS = 4
    HEX = /\A#\h{6}\z/

    def self.call(plan, media:, to:)
      new(plan, media:).render.pngsave(to.to_s, keep: :none)
      to.to_s
    end

    def initialize(plan, media:)
      @plan = plan.to_h.deep_stringify_keys
      @media = media.to_h.transform_keys(&:to_s)
    end

    def render
      width, height = canvas_size
      canvas = Raster.solid(width, height, Raster.hex_to_rgb(background_hex))
      layers.each { |layer| canvas = place(canvas, layer) }
      canvas.flatten.cast(:uchar).copy(interpretation: :srgb)
    end

    private

    def canvas_size
      CANVASES.fetch(@plan["canvas_aspect"]) do
        raise Error, "aspecto do canvas inválido: #{@plan["canvas_aspect"].inspect} (use #{CANVASES.keys.join(", ")})"
      end
    end

    def background_hex
      hex = @plan["background_hex"].to_s
      raise Error, "cor de fundo inválida: #{hex.inspect} (use #rrggbb)" unless hex.match?(HEX)

      hex
    end

    def layers
      layers = Array(@plan["layers"])
      raise Error, "o plano tem #{layers.size} camadas; o máximo é #{MAX_LAYERS}" if layers.size > MAX_LAYERS

      layers
    end

    def place(canvas, layer)
      frame = frame_for(layer["frame"])
      source = Crop.top(Raster.rgba(load(layer["media_path"])), number(layer, "crop_top_pct"))

      width_pct = number(layer, "width_pct")
      raise Error, "width_pct precisa ser maior que zero (#{layer["media_path"]})" unless width_pct.positive?

      framed = frame.call(source, width: (canvas.width * width_pct / 100.0).round)
      center_x = canvas.width * number(layer, "x_pct") / 100.0 + framed.width / 2.0
      center_y = canvas.height * number(layer, "y_pct") / 100.0 + framed.height / 2.0

      image = frame::SHADOW ? Raster.with_shadow(framed, **frame::SHADOW) : framed
      image = Raster.rotate(image, number(layer, "rotation_deg"))

      canvas.composite2(image, :over,
                        x: (center_x - image.width / 2.0).round,
                        y: (center_y - image.height / 2.0).round).cast(:uchar)
    end

    def frame_for(name)
      return FRAMES[name] if FRAMES.key?(name)
      raise Error, "moldura phone ainda não é suportada" if name == "phone"

      raise Error, "moldura inválida: #{name.inspect}"
    end

    def load(media_path)
      path = @media[media_path.to_s]
      raise Error, "mídia não encontrada para a camada: #{media_path}" if path.nil? || !File.file?(path)

      Vips::Image.new_from_file(path.to_s).autorot
    rescue Vips::Error
      raise Error, "não foi possível ler a mídia da camada: #{media_path}"
    end

    def number(layer, key)
      Float(layer[key])
    rescue ArgumentError, TypeError
      raise Error, "#{key} inválido na camada #{layer["media_path"]}: #{layer[key].inspect}"
    end
  end
end
