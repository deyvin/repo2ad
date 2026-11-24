require "test_helper"
require "tmpdir"
require_relative "../../support/media_fixtures"

module Media
  class ProbeTest < ActiveSupport::TestCase
    include MediaFixtures

    setup do
      @dir = Dir.mktmpdir("probe-test")
    end

    teardown do
      FileUtils.remove_entry(@dir)
    end

    test "vídeo 9:16 de 10 s" do
      path = make_video(@dir, "v916.mp4", size: "270x480", duration: 10)

      result = Probe.call(path)

      assert_equal 270, result.width
      assert_equal 480, result.height
      assert_in_delta 10.0, result.duration, 0.2
      assert_equal "9:16", result.aspect
    end

    test "vídeo 16:9 de 5 s" do
      path = make_video(@dir, "h169.mp4", size: "480x270", duration: 5)

      result = Probe.call(path)

      assert_equal 480, result.width
      assert_equal 270, result.height
      assert_in_delta 5.0, result.duration, 0.2
      assert_equal "16:9", result.aspect
    end

    test "imagem 4:5 não tem duração" do
      path = make_image(@dir, "i45.png", size: "400x500")

      result = Probe.call(path)

      assert_equal 400, result.width
      assert_equal 500, result.height
      assert_nil result.duration
      assert_equal "4:5", result.aspect
    end

    test "JPEG não tem duração, mesmo com o format.duration falso do demuxer image2" do
      path = make_image(@dir, "foto.jpg", size: "800x1000")

      result = Probe.call(path)

      assert_equal 800, result.width
      assert_equal 1000, result.height
      assert_nil result.duration
      assert_equal "4:5", result.aspect
    end

    test "WEBP não tem duração" do
      path = make_image(@dir, "foto.webp", size: "400x500")

      result = Probe.call(path)

      assert_nil result.duration
      assert_equal "4:5", result.aspect
    end

    test "tolerância de 2% ainda reconhece o rótulo" do
      # 1000x1800 tem razão 0,5556, 1,2% abaixo de 9:16
      path = make_image(@dir, "quase916.png", size: "1000x1800")

      assert_equal "9:16", Probe.call(path).aspect
    end

    test "aspecto fora da lista vira a razão como texto" do
      path = make_image(@dir, "quatro_tres.png", size: "640x480")

      assert_equal "1.33", Probe.call(path).aspect
    end

    test "vídeo com rotação de celular troca largura e altura" do
      # Gravado como 480x270 e remuxado com rotação de 90 graus (matriz de exibição): exibido em 270x480, que é 9:16
      base = make_video(@dir, "base.mp4", size: "480x270", duration: 2)
      path = File.join(@dir, "girado.mp4")
      ffmpeg("-display_rotation", "90", "-i", base, "-c", "copy", path)

      result = Probe.call(path)

      assert_equal 270, result.width
      assert_equal 480, result.height
      assert_equal "9:16", result.aspect
    end

    test "arquivo inválido levanta Probe::Error com mensagem em português" do
      path = File.join(@dir, "texto.mp4")
      File.write(path, "isto não é um vídeo")

      error = assert_raises(Probe::Error) { Probe.call(path) }

      assert_equal "arquivo inválido ou ilegível", error.message
    end

    test "arquivo inexistente levanta Probe::Error" do
      assert_raises(Probe::Error) { Probe.call(File.join(@dir, "nao_existe.mp4")) }
    end
  end
end
