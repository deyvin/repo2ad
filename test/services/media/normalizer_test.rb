require "test_helper"
require "vips"

class Media::NormalizerTest < ActiveSupport::TestCase
  setup { @dir = Dir.mktmpdir("normalizer") }
  teardown { FileUtils.rm_rf(@dir) }

  test "HEIC vira JPEG" do
    out = Media::Normalizer.call(file_fixture("sample.heic"), max_side: 2048, dest_dir: @dir)

    assert_equal ".jpg", File.extname(out)
    assert_equal "\xFF\xD8".b, File.binread(out, 2)
    image = Vips::Image.new_from_file(out)
    assert_equal [ 120, 80 ], [ image.width, image.height ]
  end

  test "aplica a rotação do EXIF e remove o EXIF" do
    source = File.join(@dir, "rotated.jpg")
    image = Vips::Image.black(40, 20, bands: 3).copy(interpretation: :srgb)
    image = image.mutate { |m| m.set_type!(GObject::GINT_TYPE, "orientation", 6) }
    image.jpegsave(source, keep: :all)
    assert_equal 6, Vips::Image.new_from_file(source).get("orientation")

    out = Media::Normalizer.call(source, max_side: 2048, dest_dir: @dir)
    result = Vips::Image.new_from_file(out)

    assert_equal [ 20, 40 ], [ result.width, result.height ]
    assert_equal 0, result.get_typeof("exif-data")
  end

  test "reduz o lado maior para max_side" do
    source = solid_jpeg("wide.jpg", 3000, 1000)

    result = Vips::Image.new_from_file(Media::Normalizer.call(source, max_side: 1568, dest_dir: @dir))

    assert_equal 1568, result.width
    assert_in_delta 523, result.height, 1
  end

  test "nunca aumenta imagem pequena e usa 2048 por padrão" do
    small = Vips::Image.new_from_file(Media::Normalizer.call(solid_jpeg("small.jpg", 100, 50), dest_dir: @dir))
    assert_equal [ 100, 50 ], [ small.width, small.height ]

    big = Vips::Image.new_from_file(Media::Normalizer.call(solid_jpeg("big.jpg", 1000, 4096), dest_dir: @dir))
    assert_equal 2048, big.height
  end

  test "PNG com transparência continua PNG com alfa" do
    source = File.join(@dir, "logo.png")
    Vips::Image.black(30, 30).new_from_image([ 200, 10, 10, 0 ]).copy(interpretation: :srgb).cast(:uchar).pngsave(source)

    out = Media::Normalizer.call(source, max_side: 2048, dest_dir: @dir)
    result = Vips::Image.new_from_file(out)

    assert_equal ".png", File.extname(out)
    assert result.has_alpha?
    assert_equal 0, result.getpoint(5, 5).last
  end

  test "screenshot PNG continua PNG" do
    out = Media::Normalizer.call(file_fixture("galeria.png"), max_side: 1568, dest_dir: @dir)

    assert_equal ".png", File.extname(out)
    assert_equal 1568, Vips::Image.new_from_file(out).width
  end

  test "arquivo inválido dá erro em português" do
    source = File.join(@dir, "nota.jpg")
    File.write(source, "isto não é uma imagem")

    error = assert_raises(Media::Normalizer::Error) { Media::Normalizer.call(source, dest_dir: @dir) }
    assert_match(/formato de imagem não suportado|arquivo inválido/, error.message)
  end

  test "arquivo que não existe dá erro em português" do
    error = assert_raises(Media::Normalizer::Error) { Media::Normalizer.call(File.join(@dir, "sumiu.png")) }
    assert_match "arquivo não encontrado", error.message
  end

  private

  def solid_jpeg(name, width, height)
    path = File.join(@dir, name)
    Vips::Image.black(width, height).new_from_image([ 90, 120, 150 ]).copy(interpretation: :srgb).cast(:uchar).jpegsave(path)
    path
  end
end
