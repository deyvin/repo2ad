require "test_helper"

class PollRenderStepJobTest < ActiveJob::TestCase
  setup do
    @dir = Dir.mktmpdir("poll")
    @result = File.join(@dir, "frame.png")
    Vips::Image.black(8, 8).new_from_image([ 1, 2, 3 ]).cast(:uchar).copy(interpretation: :srgb).pngsave(@result)
    @fake = Higgsfield::FakeGateway.new(result_path: @result)
    Higgsfield::Gateway.current = @fake

    project = Project.create!(repo_url: "https://github.com/deyvin/cabide", owner: "deyvin", name: "cabide")
    creative = project.creatives.create!(code: "H1", group: "horizontal", recipe: "kling_keyframes", aspect_ratio: "16:9")
    @step = creative.render_steps.create!(name: "end_frame", kind: "higgsfield", model: "nano_banana_2_1",
                                          hf_job_id: "fake-job-1", status: "submitted")
  end

  teardown do
    Higgsfield::Gateway.current = nil
    FileUtils.rm_rf(@dir)
  end

  test "concluído: baixa o resultado, anexa em output e marca done" do
    PollRenderStepJob.perform_now(@step)

    @step.reload
    assert_equal "done", @step.status
    assert @step.output.attached?
    assert_equal "end_frame-#{@step.id}.png", @step.output.filename.to_s
    assert_equal "image/png", @step.output.content_type
    assert_equal 1, @step.poll_attempts
    assert_equal [ :download, "https://cdn.fake.test/fake-job-1.png" ], @fake.calls.last
  end

  test "em andamento: marca running e consulta de novo em 5 s, com o mesmo prazo" do
    @fake.script("fake-job-1", :running)

    freeze_time do
      assert_enqueued_with(job: PollRenderStepJob, at: 5.seconds.from_now) do
        PollRenderStepJob.perform_now(@step)
      end
      deadline = enqueued_jobs.last["arguments"].last
      assert_equal 30.minutes.from_now.iso8601, deadline
    end
    assert_equal "running", @step.reload.status
  end

  test "respeita o poll_after_seconds da Higgsfield" do
    slow = Higgsfield::Gateway::Status.new(state: :running, result_url: nil, error: nil, poll_after: 12)
    @fake.define_singleton_method(:status) { |_| slow }

    freeze_time do
      assert_enqueued_with(job: PollRenderStepJob, at: 12.seconds.from_now) { PollRenderStepJob.perform_now(@step) }
    end
  end

  test "falha terminal grava a mensagem em português" do
    @fake.script("fake-job-1", "A Higgsfield bloqueou o resultado por conteúdo impróprio (NSFW).")

    PollRenderStepJob.perform_now(@step)

    assert_equal "failed", @step.reload.status
    assert_match "NSFW", @step.error
    refute @step.output.attached?
    assert_no_enqueued_jobs only: PollRenderStepJob
  end

  test "passou de 30 minutos: falha sem consultar" do
    PollRenderStepJob.perform_now(@step, 1.minute.ago.iso8601)

    assert_equal "failed", @step.reload.status
    assert_match "mais de 30 minutos", @step.error
    assert_empty @fake.calls
  end

  test "erro de configuração (login expirado) falha o step" do
    @fake.script("fake-job-1", Higgsfield::ConfigurationError.new("A conexão com a Higgsfield expirou."))

    PollRenderStepJob.perform_now(@step)

    assert_equal "failed", @step.reload.status
    assert_match "expirou", @step.error
  end

  test "erro transitório tenta de novo" do
    @fake.script("fake-job-1", Higgsfield::TransientError.new("timeout"))

    assert_enqueued_with(job: PollRenderStepJob) { PollRenderStepJob.perform_now(@step) }
    assert_equal "submitted", @step.reload.status
  end

  test "ignora step que não está em andamento" do
    @step.update!(status: "done")

    PollRenderStepJob.perform_now(@step)

    assert_empty @fake.calls
  end
end
