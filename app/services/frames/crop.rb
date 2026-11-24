module Frames
  # Corta um screenshot para mostrar só o topo, sem partir uma linha de texto ao meio (§6.4, decisão 007).
  #
  # Um corte só vale dentro de uma faixa de pelo menos MIN_GAP linhas em branco seguidas, e cai no meio dela.
  # Uma linha conta como "em branco" quando nenhum pixel dela foge do fundo da própria coluna (com a tinta crescida
  # INK_GROW px para os lados, para que uma haste de letra de 1 px não passe despercebida). O fundo de cada coluna é a
  # mediana vertical numa faixa de BACKGROUND_SPAN linhas: barra lateral, scrollbar, bordas e gradientes suaves viram
  # fundo; texto (traços finos e curtos na vertical) não.
  module Crop
    SEARCH_WINDOW = 0.08  # procura o corte a até 8% da altura em volta do corte pedido
    BACKGROUND_SPAN = 301 # altura (px, ímpar) da mediana que estima o fundo de cada coluna
    INK_DELTA = 24        # diferença (0-255) para o fundo a partir da qual um pixel é "tinta"
    INK_TOLERANCE = 0.002 # fração de pixels de tinta tolerada numa linha em branco (ruído de JPEG, antialias)
    MIN_GAP = 4           # linhas em branco seguidas: só uma faixa desse tamanho serve de corte
    INK_GROW = 2          # px que a tinta cresce para os lados antes de contar: haste de 1-2 px passa da tolerância

    module_function

    # keep_pct: porcentagem da altura que fica, a partir do topo. 0 ou >= 100 não corta.
    def top(image, keep_pct)
      keep_pct = keep_pct.to_f
      return image if keep_pct <= 0 || keep_pct >= 100

      target = (image.height * keep_pct / 100.0).round.clamp(1, image.height)
      blank_row = nearest_blank_row(image, target)
      image.crop(0, 0, image.width, blank_row ? blank_row + 1 : target)
    end

    # Linha no meio da faixa em branco mais próxima do alvo, ou nil se não há faixa na janela.
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
      blank = ink.map { |count| count <= limit }
      candidates = blank_bands(blank, top).filter_map do |band_top, band_bottom|
        next if band_bottom - band_top + 1 < MIN_GAP

        low = [ band_top, first ].max
        high = [ band_bottom, last ].min
        next if low > high

        ((band_top + band_bottom) / 2).clamp(low, high)
      end
      candidates.min_by { |row| [ (row - target).abs, row ] }
    end

    # Faixas contínuas de linhas em branco, em coordenadas da imagem: [primeira, última].
    def blank_bands(blank, offset)
      bands = []
      start = nil
      blank.each_with_index do |flag, index|
        if flag
          start ||= index
        elsif start
          bands << [ start + offset, index - 1 + offset ]
          start = nil
        end
      end
      bands << [ start + offset, blank.size - 1 + offset ] if start
      bands
    end

    # Quantos pixels de cada linha fogem do fundo da coluna (tinta já crescida INK_GROW px na horizontal).
    def ink_per_row(image)
      grey = image.extract_band(0, n: [ image.bands, 3 ].min).colourspace(:b_w).extract_band(0)
      span = [ BACKGROUND_SPAN, grey.height.odd? ? grey.height : grey.height - 1 ].min
      # Em float: o caminho vetorizado do rank em uchar (libvips 8.16) desloca blocos de 16 colunas.
      grey = grey.cast(:float)
      background = grey.rank(1, span, span / 2)
      ink = ((grey - background).abs > INK_DELTA).cast(:float) / 255.0
      grown = ink.rank(2 * INK_GROW + 1, 1, 2 * INK_GROW)
      _columns, rows = grown.cast(:uint).project
      rows.to_a.flatten.map(&:to_i)
    end
  end
end
