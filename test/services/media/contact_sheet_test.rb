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

    test "vídeo de 10 s gera 7 quadros numa grade de 4 colunas e 2 linhas" do
      video = make_video(@dir, "v916.mp4", size: "270x480", duration: 10)
      output = File.join(@dir, "sheet.jpg")

      result = ContactSheet.call(video, output_path: output)

      assert_equal [ 0.5, 2.5, 4.0, 5.5, 7.0, 8.5, 9.7 ], result.timestamps
      assert_equal output, result.path
      assert jpeg?(output)

      sheet = Probe.call(output)
      assert_equal 4 * ContactSheet::CELL_WIDTH, sheet.width
      assert_equal 2 * ContactSheet::CELL_HEIGHT, sheet.height
    end

    test "vídeo de 5 s pula os tempos além da duração" do
      video = make_video(@dir, "h169.mp4", size: "480x270", duration: 5)
      output = File.join(@dir, "curto.jpg")

      result = ContactSheet.call(video, output_path: output)

      assert_equal [ 0.5, 2.5, 4.0 ], result.timestamps
      assert jpeg?(output)

      sheet = Probe.call(output)
      assert_equal 3 * ContactSheet::CELL_WIDTH, sheet.width
      assert_equal ContactSheet::CELL_HEIGHT, sheet.height
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
