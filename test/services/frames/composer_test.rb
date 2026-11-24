require "test_helper"
require "vips"

class Frames::ComposerTest < ActiveSupport::TestCase
  GOLDEN = Rails.root.join("test/fixtures/files/golden/h1_start_frame.png")
  GOLDEN_OUTPUT = Rails.root.join("tmp/golden/h1_start_frame.png")
  # Diferença média por canal (0-255) aceita contra o golden; cobre variações de antialias entre versões do libvips.
  GOLDEN_TOLERANCE = 1.5

  setup { @dir = Dir.mktmpdir("composer") }
  teardown { FileUtils.rm_rf(@dir) }

  # §9 T7 / §12.3: quadro inicial do H1.
  test "golden: quadro inicial do H1" do
    plan = {
      canvas_aspect: "16:9",
      background_hex: "#f3efe7",
      layers: [
        { media_path: "docs/screenshots/galeria.png", frame: "browser",
          x_pct: 5, y_pct: 13, width_pct: 65, rotation_deg: 0, crop_top_pct: 90 },
        { media_path: "chao.jpg", frame: "print",
          x_pct: 70, y_pct: 35, width_pct: 24, rotation_deg: -7, crop_top_pct: 0 }
      ]
    }
    media = { "docs/screenshots/galeria.png" => file_fixture("galeria.png").to_s, "chao.jpg" => floor_photo }

    FileUtils.mkdir_p(GOLDEN_OUTPUT.dirname)
    Frames::Composer.call(plan, media: media, to: GOLDEN_OUTPUT)
    actual = Vips::Image.new_from_file(GOLDEN_OUTPUT.to_s)

    assert_equal [ 2752, 1536, 3 ], [ actual.width, actual.height, actual.bands ]

    if ENV["UPDATE_GOLDEN"]
      FileUtils.mkdir_p(GOLDEN.dirname)
      FileUtils.cp(GOLDEN_OUTPUT, GOLDEN)
    end
    golden = Vips::Image.new_from_file(GOLDEN.to_s)
    diff = (actual.cast(:float) - golden.cast(:float)).abs.avg

    assert_operator diff, :<=, GOLDEN_TOLERANCE,
      "quadro do H1 difere do golden (média #{diff.round(2)}); confira #{GOLDEN_OUTPUT} e rode com UPDATE_GOLDEN=1 se a mudança for intencional"
  end

  test "canvas no tamanho do aspecto e na cor de fundo" do
    { "16:9" => [ 2752, 1536 ], "9:16" => [ 1536, 2752 ], "4:5" => [ 2048, 2560 ], "1:1" => [ 2048, 2048 ] }.each do |aspect, size|
      image = Frames::Composer.new({ canvas_aspect: aspect, background_hex: "#c8432b", layers: [] }, media: {}).render

      assert_equal size, [ image.width, image.height ], aspect
      assert_equal [ 200, 67, 43 ], image.getpoint(10, 10).map(&:round), aspect
    end
  end

  test "posiciona a camada pelo canto superior esquerdo e pela largura" do
    red = solid_png("red.png", 100, 50, [ 255, 0, 0 ])
    plan = { canvas_aspect: "1:1", background_hex: "#ffffff",
             layers: [ { media_path: "red.png", frame: "none", x_pct: 10, y_pct: 20, width_pct: 50, rotation_deg: 0, crop_top_pct: 0 } ] }

    image = Frames::Composer.new(plan, media: { "red.png" => red }).render

    # 50% de 2048 = 1024 de largura, 512 de altura, a partir de (205, 410).
    assert_equal [ 255, 0, 0 ], image.getpoint(205 + 512, 410 + 256).map(&:round)
    assert_equal [ 255, 0, 0 ], image.getpoint(210, 415).map(&:round)
    assert_equal [ 255, 255, 255 ], image.getpoint(200, 405).map(&:round)
    assert_equal [ 255, 255, 255 ], image.getpoint(205 + 1030, 410 + 256).map(&:round)
  end

  test "moldura browser tem a barra com os três círculos e cantos arredondados" do
    framed = Frames::BrowserFrame.call(Frames::Raster.rgba(Vips::Image.new_from_file(solid_png("s.png", 400, 300, [ 0, 0, 255 ]))), width: 800)

    assert_equal [ 800, 64 + 600 ], [ framed.width, framed.height ]
    assert_equal [ 255, 95, 87 ], framed.getpoint(34, 32).first(3).map(&:round)
    assert_equal [ 254, 188, 46 ], framed.getpoint(60, 32).first(3).map(&:round)
    assert_equal [ 40, 200, 64 ], framed.getpoint(86, 32).first(3).map(&:round)
    assert_equal 0, framed.getpoint(0, 0).last
    assert_equal [ 0, 0, 255, 255 ], framed.getpoint(400, 400).map(&:round)
  end

  test "moldura print tem borda branca de 26 px" do
    framed = Frames::PrintFrame.call(Frames::Raster.rgba(Vips::Image.new_from_file(solid_png("p.png", 100, 100, [ 0, 0, 0 ]))), width: 252)

    assert_equal [ 252, 252 ], [ framed.width, framed.height ]
    assert_equal [ 255, 255, 255 ], framed.getpoint(12, 126).first(3)
    assert_equal [ 0, 0, 0 ], framed.getpoint(30, 126).first(3)
  end

  test "rotação gira no sentido horário em volta do centro" do
    bar = solid_png("bar.png", 400, 40, [ 0, 0, 0 ])
    plan = { canvas_aspect: "1:1", background_hex: "#ffffff",
             layers: [ { media_path: "bar.png", frame: "none", x_pct: 25, y_pct: 49, width_pct: 50, rotation_deg: 90, crop_top_pct: 0 } ] }

    image = Frames::Composer.new(plan, media: { "bar.png" => bar }).render

    # Barra de 1024x102 centrada em (1024, ~1055) vira vertical: o centro continua preto, as pontas viram fundo.
    assert_equal [ 0, 0, 0 ], image.getpoint(1024, 1055).map(&:round)
    assert_equal [ 255, 255, 255 ], image.getpoint(600, 1055).map(&:round)
    assert_equal [ 0, 0, 0 ], image.getpoint(1024, 700).map(&:round)
  end

  test "crop_top_pct corta na linha em branco mais próxima, sem partir texto" do
    # 1000 px de altura: "texto" (listras) de 450 a 560, branco no resto. Pedir 50% cairia no meio do texto.
    stripes = Vips::Image.xyz(600, 1000)
    y = stripes.extract_band(1)
    text = (y >= 450) & (y < 560) & ((stripes.extract_band(0) % 20) < 10)
    image = text.ifthenelse([ 0, 0, 0 ], [ 255, 255, 255 ]).cast(:uchar).copy(interpretation: :srgb)

    cropped = Frames::Crop.top(image, 50)

    # O texto ocupa as linhas 450 a 559: um corte com altura de 451 a 559 deixaria linha de texto dos dois lados.
    refute_includes 451..559, cropped.height, "cortou no meio do texto"
    assert_equal 1000, Frames::Crop.top(image, 0).height
    assert_equal 1000, Frames::Crop.top(image, 100).height
  end

  # Casos do QA da T7: screenshots de SaaS com barra lateral, scrollbar e gradiente.
  { "barra lateral escura" => { sidebar: true },
    "scrollbar à direita" => { scrollbar: true },
    "gradiente vertical suave com barra lateral" => { sidebar: true, gradient: true } }.each do |name, options|
    test "crop_top_pct não parte texto com #{name}" do
      image = saas_screenshot(**options)

      [ 51.2, 52, 63.3, 30.7 ].each do |pct|
        height = Frames::Crop.top(image, pct).height
        last_row = height - 1

        refute text_row?(last_row), "#{pct}%: cortou em #{height}, no meio do texto"
        refute text_row?(last_row + 1) && text_row?(last_row), "#{pct}%: cortou em #{height}"
        assert_in_delta 1000 * pct / 100, height, 80, "#{pct}%: corte longe do pedido (#{height})"
      end
    end
  end

  test "erros de plano em português" do
    assert_composer_error(/aspecto do canvas inválido/, canvas_aspect: "3:2", background_hex: "#ffffff", layers: [])
    assert_composer_error(/cor de fundo inválida/, canvas_aspect: "1:1", background_hex: "vermelho", layers: [])
    assert_composer_error(/máximo é 4/, canvas_aspect: "1:1", background_hex: "#ffffff", layers: Array.new(5) { layer("a.png") })
    assert_composer_error(/mídia não encontrada/, canvas_aspect: "1:1", background_hex: "#ffffff", layers: [ layer("sumiu.png") ])
    assert_composer_error(/phone ainda não é suportada/, canvas_aspect: "1:1", background_hex: "#ffffff",
                          layers: [ layer("a.png", frame: "phone") ], media: { "a.png" => solid_png("a.png", 10, 10, [ 0, 0, 0 ]) })
  end

  private

  def assert_composer_error(pattern, media: {}, **plan)
    error = assert_raises(Frames::Composer::Error) { Frames::Composer.new(plan, media: media).render }
    assert_match pattern, error.message
  end

  def layer(path, frame: "none")
    { media_path: path, frame: frame, x_pct: 0, y_pct: 0, width_pct: 10, rotation_deg: 0, crop_top_pct: 0 }
  end

  def solid_png(name, width, height, rgb)
    path = File.join(@dir, name)
    Vips::Image.black(width, height).new_from_image(rgb).copy(interpretation: :srgb).cast(:uchar).pngsave(path)
    path
  end

  # Linhas de "texto" de 30 px a cada 40 px (de y = k*40+5 a k*40+34), traços em diagonal como letras.
  def text_row?(row)
    (row % 40).between?(5, 34)
  end

  # Screenshot 1600x1000 de app SaaS: conteúdo claro com texto, barra lateral escura (240 px, #1e222d),
  # scrollbar à direita com o polegar entre y=200 e y=480, ou fundo em gradiente vertical suave.
  def saas_screenshot(sidebar: false, scrollbar: false, gradient: false)
    xyz = Vips::Image.xyz(1600, 1000)
    x = xyz.extract_band(0)
    y = xyz.extract_band(1)
    background = gradient ? (y * (-30.0 / 1000) + 250) : (x * 0 + 255)
    line = ((y % 40) >= 5) & ((y % 40) <= 34)
    glyph = ((x + y * 3) % 17) < 6
    content = (x >= 280) & (x <= 1400)
    image = (line & glyph & content).ifthenelse(40, background)
    image = (x < 240).ifthenelse(30, image) if sidebar
    image = (x >= 1586).ifthenelse(((y >= 200) & (y < 480)).ifthenelse(160, 236), image) if scrollbar
    image.cast(:uchar).bandjoin([ image.cast(:uchar), image.cast(:uchar) ]).copy(interpretation: :srgb)
  end

  # Foto sintética e determinística do "moletom no chão": piso de azulejo branco com rejunte e uma peça escura.
  def floor_photo
    path = File.join(@dir, "chao.jpg")
    xyz = Vips::Image.xyz(900, 1200)
    x = xyz.extract_band(0)
    y = xyz.extract_band(1)
    grout = ((x % 150) < 5) | ((y % 150) < 5)
    rug = (x > 560) & (y > 760)
    hoodie = (((x - 400) / 280.0)**2 + ((y - 560) / 340.0)**2) < 1
    image = grout.ifthenelse([ 196, 196, 200 ], [ 238, 238, 242 ])
    image = rug.ifthenelse([ 128, 128, 132 ], image)
    image = hoodie.ifthenelse([ 26, 26, 28 ], image)
    image.cast(:uchar).copy(interpretation: :srgb).jpegsave(path, Q: 95)
    path
  end
end
