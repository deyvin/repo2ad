module Frames
  # Janela de navegador (§6.4): barra de 64 px com os três círculos, campo de URL arredondado,
  # cantos de 22 px. A sombra (blur 40, y 30, ~27%) é aplicada pelo compositor.
  module BrowserFrame
    BAR_HEIGHT = 64
    CORNER_RADIUS = 22
    DOTS = %w[#ff5f57 #febc2e #28c840].freeze
    BAR_COLOR = "#f1f1f3"
    BAR_RULE = "#dcdce0"
    SHADOW = { blur: 40, offset_y: 30, opacity: 0.27 }.freeze

    module_function

    def call(image, width:)
      content = Raster.fit_width(image, width)
      content = Raster.solid(width, content.height, [ 255, 255, 255 ]).composite2(content, :over).cast(:uchar)

      framed = bar(width).join(content, :vertical)
      Raster.round_corners(framed, CORNER_RADIUS)
    end

    def bar(width)
      bar = Raster.solid(width, BAR_HEIGHT, Raster.hex_to_rgb(BAR_COLOR))
      bar = bar.insert(Raster.solid(width, 1, Raster.hex_to_rgb(BAR_RULE)), 0, BAR_HEIGHT - 1)
      DOTS.each_with_index do |color, i|
        bar = Raster.draw_pill(bar, x: 26 + i * 26, y: BAR_HEIGHT / 2 - 8, width: 16, height: 16, hex: color)
      end
      url_width = (width * 0.4).round
      Raster.draw_pill(bar, x: (width - url_width) / 2, y: 15, width: url_width, height: 34, hex: "#ffffff")
    end
  end
end
