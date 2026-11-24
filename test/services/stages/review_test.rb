require "test_helper"
require_relative "../../support/creative_fixtures"
require_relative "../../support/media_fixtures"

class Stages::ReviewTest < ActiveSupport::TestCase
  include CreativeFixtures
  include MediaFixtures

  setup do
    @project = create_cabide_project
    @dir = Dir.mktmpdir("review")
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "imagem: spec (texto e checks), medida, referências do spec e o próprio resultado; effort medium e 4000 tokens" do
    creative = reviewed_creative("I1", result: image_file(1856, 2304))
    fake = FakeClaude.new(JSON.parse(FakeClaude.fixture("p5_approve")))

    qa = Stages::Review.new(creative, client: fake).call

    assert_equal "approve_with_notes", qa["verdict"]
    call = fake.calls.sole
    assert_equal [ "medium", 4_000 ], [ call[:effort], call[:max_tokens] ]
    content = call[:messages].first[:content]
    texts = content.select { _1[:type] == "text" }.map { _1[:text] }
    spec = JSON.parse(texts[0][/\{.*\}/m])
    assert_equal p4_fixture("I1")["on_screen_copy"], spec["on_screen_copy"]
    assert_equal p4_fixture("I1")["checks"], spec["checks"]
    measured = JSON.parse(texts[1][/\{.*\}/m])
    assert_equal({ "width" => 1856, "height" => 2304, "duration_seconds" => nil, "aspect" => "4:5", "expected_aspect" => "4:5" }, measured)
    assert_includes texts, %(<user_photo path="uploads/chao.jpg" width="900" height="1200"/>)
    assert_includes texts, %(<user_photo path="uploads/catalogo.png" width="1024" height="1024"/>)
    assert_equal %(<result kind="image"/>), texts.last
    result = content.last
    assert_equal "image/jpeg", result[:source][:media_type]
    assert_operator Vips::Image.new_from_buffer(Base64.decode64(result[:source][:data]), "").height, :<=, 1568
  end

  test "vídeo: manda a contact sheet com os timestamps e a duração medida" do
    creative = reviewed_creative("V3", result: make_video(@dir, "v3.mp4", size: "540x960", duration: 10), content_type: "video/mp4")
    fake = FakeClaude.new(JSON.parse(FakeClaude.fixture("p5_approve")))

    Stages::Review.new(creative, client: fake).call

    texts = fake.calls.sole[:messages].first[:content].select { _1[:type] == "text" }.map { _1[:text] }
    measured = JSON.parse(texts[1][/\{.*\}/m])
    assert_equal "9:16", measured["aspect"]
    assert_in_delta 10.0, measured["duration_seconds"], 0.2
    assert_equal %(<result kind="contact_sheet" timestamps="0.5, 2.5, 4.0, 5.5, 7.0, 8.5, 9.7"/>), texts.last
  end

  test "regenerate sem fix_instructions volta ao modelo" do
    creative = reviewed_creative("I1", result: image_file(1856, 2304))
    broken = JSON.parse(FakeClaude.fixture("p5_regenerate")).merge("fix_instructions" => nil)
    fake = FakeClaude.new(broken, JSON.parse(FakeClaude.fixture("p5_regenerate")))

    assert_equal "regenerate", Stages::Review.new(creative, client: fake).call["verdict"]
    assert_includes fake.calls.last[:messages].last[:content], "/fix_instructions: required"
  end

  private

  def reviewed_creative(code, result:, content_type: "image/png")
    creative = create_creative(@project, code)
    creative.update!(spec: p4_fixture(code), status: "reviewing")
    File.open(result, "rb") { creative.result.attach(io: _1, filename: File.basename(result), content_type: content_type) }
    creative
  end

  def image_file(width, height)
    path = File.join(@dir, "#{width}x#{height}.png")
    Vips::Image.black(width, height).new_from_image([ 240, 238, 230 ]).cast(:uchar).copy(interpretation: :srgb).pngsave(path)
    path
  end
end
