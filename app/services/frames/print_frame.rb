module Frames
  # Foto impressa (§6.4): borda branca de 26 px e sombra mais curta que a do navegador.
  # A rotação (rotation_deg) é aplicada pelo compositor.
  module PrintFrame
    BORDER = 26
    SHADOW = { blur: 18, offset_y: 10, opacity: 0.25 }.freeze

    module_function

    def call(image, width:)
      inner = width - 2 * BORDER
      raise Composer::Error, "a moldura print precisa de largura maior que #{2 * BORDER} px" unless inner.positive?

      photo = Raster.fit_width(image, inner)
      photo = Raster.solid(photo.width, photo.height, [ 255, 255, 255 ]).composite2(photo, :over).cast(:uchar)
      photo.embed(BORDER, BORDER, photo.width + 2 * BORDER, photo.height + 2 * BORDER,
                  extend: :background, background: [ 255, 255, 255, 255 ])
    end
  end
end
