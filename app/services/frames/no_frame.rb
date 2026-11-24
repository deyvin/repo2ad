module Frames
  # Camada sem moldura: só redimensiona para a largura pedida.
  module NoFrame
    SHADOW = nil

    module_function

    def call(image, width:)
      Raster.fit_width(image, width)
    end
  end
end
