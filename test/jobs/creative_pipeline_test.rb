require "test_helper"
require_relative "../support/creative_fixtures"

# PromptCreativeJob → RenderCreativeJob → PollRenderStepJob com FakeClaude e FakeGateway (sem rede, sem créditos).
class CreativePipelineTest < ActiveJob::TestCase
  include CreativeFixtures

  setup do
    @project = create_cabide_project
    @result = File.join(Dir.mktmpdir("pipeline"), "resultado.png")
    Vips::Image.black(16, 16).new_from_image([ 9, 9, 9 ]).cast(:uchar).copy(interpretation: :srgb).pngsave(@result)
    @gateway = Higgsfield::FakeGateway.new(result_path: @result)
    Higgsfield::Gateway.current = @gateway
    @original_client = PromptCreativeJob.client_factory
  end

  teardown do
    Higgsfield::Gateway.current = nil
    PromptCreativeJob.client_factory = @original_client
  end

  test "I1 (nb_image): P4, upload das 2 referências, submit, poll e resultado no criativo" do
    creative = create_creative(@project, "I1")
    use_claude(p4_fixture("I1"))

    PromptCreativeJob.perform_now(creative)
    assert_equal "rendering", creative.reload.status
    assert_equal "nb_image", creative.spec["recipe"]

    perform_enqueued_jobs(only: RenderCreativeJob)
    submission = @gateway.submissions.sole
    assert_equal "nano_banana_2_1", submission[:model]
    assert_equal({ "aspect_ratio" => "4:5", "resolution" => "2k", "duration" => nil, "mode" => nil, "thinking_level" => "high" }, submission[:params])
    assert_equal [ { value: "fake-media-1", role: "image_references" }, { value: "fake-media-2", role: "image_references" } ], submission[:media]
    assert_equal 2, @gateway.uploads.size

    run_polls
    perform_enqueued_jobs(only: RenderCreativeJob)

    creative.reload
    assert_equal "done", creative.status
    assert creative.result.attached?
    assert_equal %w[done], creative.render_steps.pluck(:status)
  end

  test "H1 (kling_keyframes): compose local, end_frame no Nano Banana e Kling com start (upload) e end (job_id)" do
    creative = create_creative(@project, "H1")
    use_claude(p4_fixture("H1"))
    PromptCreativeJob.perform_now(creative)

    perform_enqueued_jobs(only: RenderCreativeJob)
    start_frame, end_frame, main = creative.render_steps.order(:id).to_a
    assert_equal [ "done", "submitted", "pending" ], [ start_frame, end_frame, main ].map(&:status)
    frame = Vips::Image.new_from_buffer(start_frame.output.download, "")
    assert_equal [ 2752, 1536 ], [ frame.width, frame.height ]
    assert_equal "nano_banana_2_1", @gateway.submissions.last[:model]

    run_polls
    perform_enqueued_jobs(only: RenderCreativeJob)
    kling = @gateway.submissions.last
    assert_equal "kling4_0", kling[:model]
    assert_equal({ "aspect_ratio" => "16:9", "resolution" => "1080p", "duration" => 10, "mode" => "image-to-video", "thinking_level" => nil }, kling[:params])
    start, finish = kling[:media]
    assert_equal "start_image", start[:role]
    assert_match(/\Afake-media-\d+\z/, start[:value]) # o quadro composto vai por upload
    assert_equal ".png", File.extname(@gateway.uploads.last)
    assert_equal({ value: end_frame.reload.hf_job_id, role: "end_image" }, finish) # job_id direto, sem baixar

    run_polls
    perform_enqueued_jobs(only: RenderCreativeJob)
    creative.reload
    assert_equal "done", creative.status
    assert_equal main.reload.output.blob, creative.result.blob
  end

  test "o 1º poll já sai com o prazo de 30 min, e um retry da 1ª execução mantém o mesmo prazo" do
    creative = create_creative(@project, "I1")
    use_claude(p4_fixture("I1"))
    PromptCreativeJob.perform_now(creative)

    freeze_time do
      perform_enqueued_jobs(only: RenderCreativeJob)
      poll = enqueued_jobs.find { _1["job_class"] == "PollRenderStepJob" }
      deadline = poll["arguments"].last
      assert_equal 30.minutes.from_now.iso8601, deadline

      step = creative.reload.render_steps.sole
      @gateway.script(step.hf_job_id, Higgsfield::TransientError.new("timeout"))
      clear_enqueued_jobs
      PollRenderStepJob.perform_now(step, deadline)
      retry_job = enqueued_jobs.find { _1["job_class"] == "PollRenderStepJob" }
      assert_equal deadline, retry_job["arguments"].last
    end
  end

  test "falha num step remoto falha o criativo com a mensagem" do
    creative = create_creative(@project, "I1")
    use_claude(p4_fixture("I1"))
    PromptCreativeJob.perform_now(creative)
    perform_enqueued_jobs(only: RenderCreativeJob)
    @gateway.script(creative.reload.render_steps.sole.hf_job_id, "A Higgsfield bloqueou o resultado por conteúdo impróprio (NSFW).")

    run_polls

    creative.reload
    assert_equal "failed", creative.status
    assert_equal "O passo main falhou: A Higgsfield bloqueou o resultado por conteúdo impróprio (NSFW).", creative.error
    assert_no_enqueued_jobs(only: RenderCreativeJob)
  end

  test "P4 inválido três vezes: criativo failed em português" do
    creative = create_creative(@project, "I1")
    use_claude({}, {}, {})

    PromptCreativeJob.perform_now(creative)

    assert_equal "failed", creative.reload.status
    assert_match "P4 (prompt de geração) devolveu uma resposta fora do formato esperado", creative.error
  end

  test "receita ainda não disponível falha sem chamar o modelo" do
    creative = create_creative(@project, "H1")
    creative.update!(recipe: "kling_reference")
    fake = use_claude

    PromptCreativeJob.perform_now(creative)

    assert_equal "failed", creative.reload.status
    assert_match "kling_reference ainda não está disponível", creative.error
    assert_empty fake.calls
  end

  private

  def use_claude(*responses)
    fake = FakeClaude.new(*responses)
    PromptCreativeJob.client_factory = -> { fake }
    fake
  end

  def run_polls
    perform_enqueued_jobs(only: PollRenderStepJob)
  end
end
