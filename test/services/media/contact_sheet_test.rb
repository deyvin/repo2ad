require "test_helper"
require "tmpdir"
require_relative "../../support/media_fixtures"

module Media
  class ContactSheetTest < ActiveSupport::TestCase
    include MediaFixtures

    setup do
      @dir = Dir.mktmpdir("contact-test")
    end

    teardown do
      FileUtils.remove_entry(@dir)
    end

    test "vídeo 9:16 de 10 s gera 7 quadros em grade 4x2 de células 270x480" do
      video = make_video(@dir, "v916.mp4", size: "270x480", duration: 10)
      output = File.join(@dir, "sheet.jpg")

      result = ContactSheet.call(video, output_path: output)

      assert_equal [ 0.5, 2.5, 4.0, 5.5, 7.0, 8.5, 9.7 ], result.timestamps
      assert_equal output, result.path
      assert jpeg?(output)

      sheet = Probe.call(output)
      assert_equal [ 1080, 960 ], [ sheet.width, sheet.height ]
    end

    test "célula sem quadro sai preta" do
      video = make_video(@dir, "v916.mp4", size: "270x480", duration: 10)
      output = ContactSheet.call(video, output_path: File.join(@dir, "sheet.jpg")).path

      # 8ª célula (índice 7): coluna 3, linha 1, centro em (945, 720)
      r, g, b = pixel_at(output, 945, 720)

      assert_operator [ r, g, b ].max, :<, 20
    end

    test "vídeo 16:9 usa células 480x270 e mantém 4 colunas" do
      video = make_video(@dir, "h169.mp4", size: "480x270", duration: 10)
      output = File.join(@dir, "h169.jpg")

      ContactSheet.call(video, output_path: output)

      sheet = Probe.call(output)
      assert_equal [ 1920, 540 ], [ sheet.width, sheet.height ]
    end

    test "vídeo 4:5 usa células 384x480" do
      video = make_video(@dir, "v45.mp4", size: "320x400", duration: 10)
      output = File.join(@dir, "v45.jpg")

      ContactSheet.call(video, output_path: output)

      sheet = Probe.call(output)
      assert_equal [ 1536, 960 ], [ sheet.width, sheet.height ]
    end

    test "vídeo de 5 s em 16:9 pula os tempos além da duração" do
      video = make_video(@dir, "curto.mp4", size: "480x270", duration: 5)
      output = File.join(@dir, "curto.jpg")

      result = ContactSheet.call(video, output_path: output)

      assert_equal [ 0.5, 2.5, 4.0 ], result.timestamps
      assert jpeg?(output)

      sheet = Probe.call(output)
      assert_equal [ 1440, 270 ], [ sheet.width, sheet.height ]
    end

    test "imagem não é vídeo" do
      image = make_image(@dir, "foto.jpg", size: "800x1000")

      error = assert_raises(ContactSheet::Error) do
        ContactSheet.call(image, output_path: File.join(@dir, "x.jpg"))
      end

      assert_match "não é um vídeo", error.message
    end

    test "vídeo mais curto que o primeiro tempo levanta erro" do
      video = make_video(@dir, "muito_curto.mp4", size: "270x480", duration: 0.4)

      error = assert_raises(ContactSheet::Error) do
        ContactSheet.call(video, output_path: File.join(@dir, "x.jpg"))
      end

      assert_match "curto demais", error.message
    end

    test "sem output_path grava em tmp/contact_sheets" do
      video = make_video(@dir, "padrao.mp4", size: "270x480", duration: 3)

      result = ContactSheet.call(video)

      assert result.path.start_with?(Rails.root.join("tmp", "contact_sheets").to_s)
      assert jpeg?(result.path)
    ensure
      FileUtils.rm_f(result.path) if result
    end
  end
end
