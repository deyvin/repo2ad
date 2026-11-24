module Frames
  # Corta um screenshot para mostrar só o topo, sem partir uma linha de texto ao meio (§6.4, decisão 007).
  #
  # Uma linha conta como "em branco" quando nenhum pixel dela foge do fundo da própria coluna. O fundo
  # de cada coluna é a mediana vertical numa faixa de BACKGROUND_SPAN linhas: barra lateral, scrollbar,
  # bordas e gradientes suaves viram fundo; texto (traços finos e curtos na vertical) não.
  module Crop
    SEARCH_WINDOW = 0.08  # procura a linha em branco a até 8% da altura em volta do corte pedido
    BACKGROUND_SPAN = 301 # altura (px, ímpar) da mediana que estima o fundo de cada coluna
    INK_DELTA = 24        # diferença (0-255) para o fundo a partir da qual um pixel é "tinta"
    INK_TOLERANCE = 0.002 # fração de pixels de tinta tolerada numa linha em branco (ruído, antialias)

    module_function

    # keep_pct: porcentagem da altura que fica, a partir do topo. 0 ou >= 100 não corta.
    def top(image, keep_pct)
      keep_pct = keep_pct.to_f
      return image if keep_pct <= 0 || keep_pct >= 100

      target = (image.height * keep_pct / 100.0).round.clamp(1, image.height)
      blank_row = nearest_blank_row(image, target)
      image.crop(0, 0, image.width, blank_row ? blank_row + 1 : target)
    end

    def nearest_blank_row(image, target)
      window = (image.height * SEARCH_WINDOW).round
      first = (target - window).clamp(1, image.height - 1)
      last = (target + window).clamp(1, image.height - 1)

      # A faixa analisada ganha meia mediana de margem para o fundo das bordas da janela também ser estimado.
      margin = BACKGROUND_SPAN / 2
      top = [ first - margin, 0 ].max
      bottom = [ last + margin, image.height - 1 ].min
      ink = ink_per_row(image.crop(0, top, image.width, bottom - top + 1))

      limit = (image.width * INK_TOLERANCE).floor
      blank = (first..last).select { |row| ink[row - top] <= limit }
      blank.min_by { |row| [ (row - target).abs, row ] }
    end

    # Quantos pixels de cada linha fogem do fundo da coluna.
    def ink_per_row(image)
      grey = image.extract_band(0, n: [ image.bands, 3 ].min).colourspace(:b_w).extract_band(0)
      span = [ BACKGROUND_SPAN, grey.height.odd? ? grey.height : grey.height - 1 ].min
      # Em float: o caminho vetorizado do rank em uchar (libvips 8.16) desloca blocos de 16 colunas.
      grey = grey.cast(:float)
      background = grey.rank(1, span, span / 2)
      ink = ((grey - background).abs > INK_DELTA) / 255
      _columns, rows = ink.cast(:uint).project
      rows.to_a.flatten.map(&:to_i)
    end
  end
end
