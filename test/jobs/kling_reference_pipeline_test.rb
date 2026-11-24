require "test_helper"
require_relative "../support/creative_fixtures"

# T10: V3 (kling_reference, 9:16, 10 s) a partir da foto 3:4 do chão. O quadro inicial sai em 9:16 (D6),
# medido com o Media::Probe no arquivo que o pipeline produz. Sem rede, sem créditos.
class KlingReferencePipelineTest < ActiveJob::TestCase
  include CreativeFixtures

  setup do
    @project = create_cabide_project
    @dir = Dir.mktmpdir("v3")
    @original_client = PromptCreativeJob.client_factory
  end

  teardown do
    Higgsfield::Gateway.current = nil
    PromptCreativeJob.client_factory = @original_client
    FileUtils.rm_rf(@dir)
  end

  test "a foto do chão é 3:4 de verdade" do
    chao = @project.media_inputs.find_by!(path: "uploads/chao.jpg")
    aspect = chao.file.blob.open { Media::Probe.call(_1.path).aspect }

    assert_equal "3:4", aspect
  end

  test "V3 com quadro inicial do Nano Banana (outpaint): start_frame em 9:16 e Kling com start + até 4 referências" do
    gateway = use_gateway(image(1536, 2752)) # o fake devolve o quadro no aspecto declarado (9:16)
    creative = run_prompt("V3", p4_fixture("V3"))

    perform_enqueued_jobs(only: RenderCreativeJob)
    nano = gateway.submissions.last
    assert_equal "nano_banana_2_1", nano[:model]
    assert_equal "9:16", nano[:params]["aspect_ratio"]
    assert_match(/outpaint/, nano[:prompt])

    perform_enqueued_jobs(only: PollRenderStepJob)
    start_frame = creative.reload.render_steps.find_by!(name: "start_frame")
    assert_equal "9:16", start_frame.output.blob.open { Media::Probe.call(_1.path).aspect }

    perform_enqueued_jobs(only: RenderCreativeJob)
    kling = gateway.submissions.last
    assert_equal "kling4_0", kling[:model]
    assert_equal({ "aspect_ratio" => "9:16", "resolution" => "1080p", "duration" => 10, "mode" => "image-to-video", "thinking_level" => nil }, kling[:params])
    assert_equal({ value: start_frame.hf_job_id, role: "start_image" }, kling[:media].find { _1[:role] == "start_image" })
    assert_equal 1, kling[:media].count { _1[:role] == "image_references" }

    perform_enqueued_jobs(only: PollRenderStepJob)
    perform_enqueued_jobs(only: RenderCreativeJob)
    assert_equal "done", creative.reload.status
  end

  test "V3 com quadro inicial composto (foto 3:4 sobre fundo da marca): arquivo real em 9:16" do
    gateway = use_gateway(image(64, 64))
    spec = p4_fixture("V3")
    spec["steps"][0] = {
      "name" => "start_frame", "kind" => "compose", "model" => nil, "prompt" => nil,
      "params" => { "aspect_ratio" => "9:16", "resolution" => "2k", "duration" => nil, "mode" => nil, "thinking_level" => nil },
      "inputs" => { "image_references" => [], "start_image" => nil, "end_image" => nil },
      "compose_plan" => { "canvas_aspect" => "9:16", "background_hex" => "#f3efe7",
                          "layers" => [ { "media_path" => "uploads/chao.jpg", "frame" => "none", "x_pct" => 0, "y_pct" => 21.9,
                                          "width_pct" => 100, "rotation_deg" => 0, "crop_top_pct" => 0 } ] }
    }
    creative = run_prompt("V3", spec)

    perform_enqueued_jobs(only: RenderCreativeJob)

    start_frame = creative.reload.render_steps.find_by!(name: "start_frame")
    assert_equal "done", start_frame.status
    assert_equal "9:16", start_frame.output.blob.open { Media::Probe.call(_1.path).aspect }
    kling = gateway.submissions.sole
    assert_equal "kling4_0", kling[:model]
    assert_match(/\Afake-media-\d+\z/, kling[:media].find { _1[:role] == "start_image" }[:value])
  end

  test "quadro inicial fora do aspecto: o Kling não é submetido e o criativo falha com mensagem" do
    gateway = use_gateway(image(900, 1200)) # a Higgsfield devolveu 3:4
    creative = run_prompt("V3", p4_fixture("V3"))
    perform_enqueued_jobs(only: RenderCreativeJob)
    perform_enqueued_jobs(only: PollRenderStepJob)

    perform_enqueued_jobs(only: RenderCreativeJob)

    assert_equal [ "nano_banana_2_1" ], gateway.submissions.map { _1[:model] }
    creative.reload
    assert_equal "failed", creative.status
    assert_equal "O passo main falhou: o quadro inicial saiu em 3:4, mas o vídeo é 9:16; o Kling herdaria o aspecto errado", creative.error
  end

  test "kling_magic roda pelo pipeline da kling_reference" do
    use_gateway(image(1536, 2752))
    spec = p4_fixture("V3").merge("recipe" => "kling_magic")
    creative = create_creative(@project, "V3")
    creative.update!(recipe: "kling_magic")
    fake = FakeClaude.new(spec)
    PromptCreativeJob.client_factory = -> { fake }

    PromptCreativeJob.perform_now(creative)

    assert_equal Recipes::KlingReference, Recipes.for("kling_magic")
    assert_equal "rendering", creative.reload.status
    assert_includes fake.calls.first[:system][1][:text], "### 6.3 `kling_magic`"
  end

  test "P4: mais de 4 referências do produto ou kling fora de image-to-video são recusados" do
    creative = create_creative(@project, "V3")
    stage = Stages::CreativeSpec.new(creative)
    spec = p4_fixture("V3")
    assert_empty stage.validation_errors(spec)

    spec["steps"][1]["inputs"]["image_references"] = Array.new(5, "uploads/catalogo.png")
    spec["steps"][1]["params"]["mode"] = "reference-to-video"
    errors = stage.validation_errors(spec).join("\n")

    assert_includes errors, "at most 4 product references for this recipe (got 5)"
    assert_includes errors, %(kling needs mode "image-to-video")
  end

  private

  def use_gateway(result_path)
    Higgsfield::Gateway.current = Higgsfield::FakeGateway.new(result_path: result_path)
  end

  def run_prompt(code, spec)
    creative = create_creative(@project, code)
    PromptCreativeJob.client_factory = -> { FakeClaude.new(spec) }
    PromptCreativeJob.perform_now(creative)
    assert_equal "rendering", creative.reload.status, creative.error
    creative
  end

  def image(width, height)
    path = File.join(@dir, "#{width}x#{height}.png")
    Vips::Image.black(width, height).new_from_image([ 20, 20, 20 ]).cast(:uchar).copy(interpretation: :srgb).pngsave(path)
    path
  end
end
