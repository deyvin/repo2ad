require "test_helper"

module Frames
  # Corte de screenshot: nenhum corte pode deixar tinta da mesma linha de texto dos dois lados.
  # A "régua de tinta" é a faixa exata de linhas que cada cena desenha como texto (sem antialias).
  class CropTest < ActiveSupport::TestCase
    WIDTH = 1600
    HEIGHT = 1000
    DESCENDERS = %w[g j p q y].freeze
    ACCENTED = %w[Á É Ç].freeze

    # Imagem com régua de tinta: desenha retângulos e marca quais linhas têm texto.
    class Scene
      def initialize(background, width: WIDTH, height: HEIGHT)
        @background = background
        @width = width
        @height = height
        @rects = []
        @photos = []
        @text_rows = Array.new(height, false)
      end

      def text_row?(row)
        row.between?(0, @height - 1) && @text_rows[row]
      end

      # A imagem é montada na primeira leitura: desenhar retângulo a retângulo copiaria a cena inteira a cada um.
      def image
        @image ||= begin
          base = Vips::Image.black(@width, @height).new_from_image(@background).cast(:uchar).copy(interpretation: :srgb)
          base = @photos.reduce(base) { |canvas, (x, y, photo)| canvas.insert(photo, x, y) }
          base.mutate { |canvas| @rects.each { |x, y, w, h, rgb| canvas.draw_rect!(rgb, x, y, w, h, fill: true) } }
        end
      end

      def rect(x, y, width, height, rgb, text: false)
        @rects << [ x, y, width, height, rgb ]
        return unless text

        (y...(y + height)).each { |row| @text_rows[row] = true if row.between?(0, @height - 1) }
      end

      # Linha de texto com haste por letra, barra no meio, descendentes em gjpqy e acento em ÁÉÇ.
      def text(x, y, size, string, rgb)
        advance = (size * 0.55).round
        stem = [ 1, size / 9 ].max
        string.each_char.with_index do |char, i|
          gx = x + i * advance
          rect(gx, y, stem, size, rgb, text: true)
          rect(gx, y + size / 2, advance * 6 / 10, stem, rgb, text: true)
          rect(gx + advance / 3, y + size, stem, size / 4, rgb, text: true) if DESCENDERS.include?(char)
          rect(gx + advance / 3, y - size / 4, advance / 3, stem, rgb, text: true) if ACCENTED.include?(char)
          rect(gx + advance / 3, y + size + size / 5, stem, stem * 2, rgb, text: true) if char == "Ç"
        end
      end

      def photo(x, y, width, height, level, sigma: 4)
        noise = Vips::Image.gaussnoise(width, height, mean: level, sigma: sigma).cast(:uchar)
        @photos << [ x, y, noise.bandjoin([ noise, noise ]).copy(interpretation: :srgb) ]
      end
    end

    test "sidebar escura com texto: nenhum corte no meio do texto" do
      scene = Scene.new([ 248, 249, 250 ])
      scene.rect(0, 0, 240, HEIGHT, [ 30, 34, 45 ])
      lines(scene, x: 280, size: 22, color: [ 40, 40, 40 ])

      assert_clean_cuts(scene)
    end

    test "dark mode: texto claro em fundo escuro, nenhum corte no meio do texto" do
      scene = Scene.new([ 24, 26, 31 ])
      lines(scene, x: 120, size: 22, color: [ 230, 230, 230 ])

      assert_clean_cuts(scene)
    end

    test "cores e tamanhos variados com gjpqy ÁÉÇ, nenhum corte no meio do texto" do
      scene = Scene.new([ 248, 249, 250 ])
      y = 30
      [ 12, 18, 28, 44, 60 ].each_with_index do |size, index|
        color = [ [ 20, 20, 20 ], [ 180, 40, 40 ], [ 30, 90, 180 ], [ 90, 90, 90 ], [ 10, 120, 60 ] ][index]
        scene.text(120, y, size, "gjpqy ÁÉÇ painel pago", color)
        y += size * 2 + 30
      end
      lines(scene, x: 120, size: 16, color: [ 40, 40, 40 ], from: y, pitch: 44)

      assert_clean_cuts(scene)
    end

    test "tabela com regras de 1 px e texto nas células, nenhum corte no meio do texto" do
      scene = Scene.new([ 255, 255, 255 ])
      (0...HEIGHT).step(30) { |y| scene.rect(0, y, WIDTH, 1, [ 120, 120, 120 ]) }
      (0...(HEIGHT / 30)).each do |k|
        [ 100, 400, 700 ].each { |x| scene.text(x, k * 30 + 9, 12, "pago gjpqy", [ 30, 30, 30 ]) }
      end

      assert_clean_cuts(scene)
    end

    test "foto escura grande ao lado do texto: pode cortar na foto, mas não no texto" do
      scene = Scene.new([ 255, 255, 255 ])
      lines(scene, x: 60, size: 22, color: [ 30, 30, 30 ])
      scene.photo(900, 100, 600, 800, 35)

      assert_clean_cuts(scene)
    end

    test "uma haste de 1 px sozinha numa linha não vira faixa de corte" do
      scene = Scene.new([ 255, 255, 255 ])
      scene.text(100, 400, 60, "p", [ 0, 0, 0 ])

      assert_clean_cuts(scene)
    end

    test "bloco de texto cheio: o corte cai fora dele, nunca no meio" do
      scene = Scene.new([ 255, 255, 255 ])
      scene.rect(0, 300, WIDTH, 40, [ 0, 0, 0 ], text: true)

      assert_clean_cuts(scene)
    end

    test "galeria real (2880x1800): cortes sem texto dos dois lados, desvio até 8%, sem travar (menos de 3 s)" do
      # Imagem já decodificada na memória; o tempo é o do corte, o menor de três, porque a suíte roda em paralelo.
      image = Vips::Image.new_from_file(Rails.root.join("test/fixtures/files/galeria.png").to_s)
                         .copy(interpretation: :srgb).copy_memory
      assert_equal [ 2880, 1800 ], [ image.width, image.height ]

      times = Array.new(3) do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Frames::Crop.top(image, 50)
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      end
      height = Frames::Crop.top(image, 50).height

      # Garantia: o corte não trava. O limite é folgado porque a suíte roda em paralelo e a carga varia.
      assert_operator times.min, :<, 3.0
      assert_operator (height - 0.5 * image.height).abs, :<=, 0.08 * image.height + 2
    end

    private

    PHRASES = [ "painel pago gjpqy ÁÉÇ", "resumo de vendas", "Ágil, pronto: gjpqy", "fotos da peça ÉÇ",
                "pago em julho", "última atualização" ].freeze

    # Linhas de texto com conteúdo e posição que variam de uma linha para outra, como texto real:
    # hastes alinhadas na mesma coluna em todas as linhas deixariam a mediana de fundo da coluna errada.
    def lines(scene, x:, size:, color:, from: 20, pitch: 40)
      (from..(HEIGHT - 40)).step(pitch).with_index do |y, index|
        scene.text(x + (index * 17) % 31, y, size, PHRASES[index % PHRASES.size], color)
      end
    end

    def assert_clean_cuts(scene)
      image = scene.image
      violations = []
      worst_deviation = 0.0

      10.0.step(90.0, 1.7) do |pct|
        height = Frames::Crop.top(image, pct).height
        next if height >= image.height

        cut = height - 1
        violations << pct.round(1) if scene.text_row?(cut) && scene.text_row?(cut + 1)
        worst_deviation = [ worst_deviation, (height - pct * image.height / 100.0).abs ].max
      end

      assert_empty violations, "cortes que deixam texto dos dois lados, em % da altura"
      assert_operator worst_deviation, :<=, 0.08 * image.height + 2, "desvio maior que 8% da altura"
    end
  end
end
