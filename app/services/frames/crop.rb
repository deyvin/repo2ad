module Frames
  # Corta um screenshot para mostrar só o topo, sem partir uma linha de texto ao meio (§6.4).
  module Crop
    BLANK_ROW_STDDEV = 3.0 # desvio padrão máximo (0-255) para uma linha contar como "em branco"
    SEARCH_WINDOW = 0.08   # procura a linha em branco a até 8% da altura em volta do corte pedido

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
      stddevs = row_stddevs(image.crop(0, first, image.width, last - first + 1))

      blank = stddevs.each_index.select { |i| stddevs[i] <= BLANK_ROW_STDDEV }.map { |i| first + i }
      blank.min_by { |row| [ (row - target).abs, row ] }
    end

    def row_stddevs(image)
      grey = image.extract_band(0, n: [ image.bands, 3 ].min).colourspace(:b_w).extract_band(0).cast(:double)
      _columns, sums = grey.project
      _columns, squares = (grey * grey).project
      width = grey.width.to_f
      sums.to_a.flatten.zip(squares.to_a.flatten).map do |sum, square|
        mean = sum / width
        Math.sqrt([ square / width - mean * mean, 0 ].max)
      end
    end
  end
end
