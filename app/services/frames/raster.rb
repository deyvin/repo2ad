require "vips"

module Frames
  # Operações de imagem compartilhadas pelas molduras e pelo compositor. Tudo em sRGB com alfa (4 bandas).
  module Raster
    module_function

    def rgba(image)
      image = image.colourspace(:srgb) unless image.interpretation == :srgb
      image = image.bandjoin(255) unless image.has_alpha?
      image.cast(:uchar)
    end

    def solid(width, height, rgb, alpha: 255)
      Vips::Image.black(width, height).new_from_image([ *rgb, alpha ]).copy(interpretation: :srgb).cast(:uchar)
    end

    def hex_to_rgb(hex)
      hex.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) }
    end

    # Redimensiona para exatamente `width` px de largura (a altura segue a proporção).
    def fit_width(image, width)
      resized = image.resize(width.to_f / image.width)
      return resized.crop(0, 0, width, resized.height) if resized.width > width
      return resized.embed(0, 0, width, resized.height, extend: :copy) if resized.width < width

      resized
    end

    # Cantos arredondados: multiplica o alfa por uma máscara com borda suavizada.
    def round_corners(image, radius)
      alpha = (image.extract_band(3) * rounded_mask(image.width, image.height, radius) / 255.0).cast(:uchar)
      image.extract_band(0, n: 3).bandjoin(alpha)
    end

    # Máscara 0-255 de um retângulo de cantos arredondados (sem SVG: o Rails bloqueia o svgload do libvips).
    def rounded_mask(width, height, radius)
      xyz = Vips::Image.xyz(width, height)
      x = xyz.extract_band(0)
      y = xyz.extract_band(1)
      nearest_x = (x < radius).ifthenelse(radius, (x > width - 1 - radius).ifthenelse(width - 1 - radius, x))
      nearest_y = (y < radius).ifthenelse(radius, (y > height - 1 - radius).ifthenelse(height - 1 - radius, y))
      distance = ((x - nearest_x)**2 + (y - nearest_y)**2)**0.5
      ((distance * -1 + (radius + 0.5)) * 255).cast(:uchar)
    end

    # Pílula ou círculo preenchido, com borda suavizada, desenhado sobre `image` (RGBA).
    def draw_pill(image, x:, y:, width:, height:, hex:)
      mask = rounded_mask(width, height, height / 2.0)
      pill = solid(width, height, hex_to_rgb(hex), alpha: 0).extract_band(0, n: 3).bandjoin(mask)
      image.composite2(pill, :over, x: x, y: y).cast(:uchar)
    end

    # Sombra projetada como CSS box-shadow (blur, deslocamento y, opacidade). A margem é igual nos
    # quatro lados, então a moldura fica centrada na imagem devolvida (a rotação gira em torno dela).
    def with_shadow(image, blur:, offset_y:, opacity:)
      pad = (blur * 1.5).ceil + offset_y.abs
      width = image.width + 2 * pad
      height = image.height + 2 * pad
      sigma = blur / 2.0

      alpha = image.extract_band(3).embed(pad, pad + offset_y, width, height, extend: :black)
      shadow_alpha = (alpha.gaussblur(sigma) * opacity).cast(:uchar)
      shadow = Vips::Image.black(width, height, bands: 3).cast(:uchar).bandjoin(shadow_alpha).copy(interpretation: :srgb)
      framed = image.embed(pad, pad, width, height, extend: :background, background: [ 0, 0, 0, 0 ])

      shadow.composite2(framed, :over).cast(:uchar)
    end

    # Gira em graus no sentido horário (como CSS rotate), com fundo transparente e bordas suaves.
    def rotate(image, degrees)
      return image if degrees.to_f.zero?

      image.premultiply
           .similarity(angle: degrees.to_f, background: [ 0, 0, 0, 0 ], interpolate: Vips::Interpolate.new(:bilinear))
           .unpremultiply
           .cast(:uchar)
    end
  end
end
