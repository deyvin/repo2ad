require "test_helper"
require_relative "../../support/fake_mcp_session"

class Higgsfield::McpGatewayTest < ActiveSupport::TestCase
  # HTTP de mentira para o PUT pré-assinado e o download.
  class FakeHttp
    attr_reader :puts, :gets

    def initialize = (@puts = []; @gets = [])
    def put(url, bytes, content_type) = @puts << [ url, bytes.bytesize, content_type ]

    def get(url)
      @gets << url
      Higgsfield::Gateway::Download.new(io: StringIO.new("png"), content_type: "image/png", filename: "x.png")
    end
  end

  setup do
    @http = FakeHttp.new
    @dir = Dir.mktmpdir("gateway")
  end
  teardown { FileUtils.rm_rf(@dir) }

  test "upload: media_upload, PUT pré-assinado e media_confirm" do
    path = File.join(@dir, "start.png")
    File.binwrite(path, "\x89PNG\r\n\x1a\n" + "x" * 10)
    session = FakeMcpSession.new(
      "media_upload" => { "uploads" => [ { "upload_url" => "https://s3.test/put", "media_id" => "m-1" } ] },
      "media_confirm" => { "confirmed" => [ "m-1" ] }
    )

    media_id = gateway(session).upload(path)

    assert_equal "m-1", media_id
    assert_equal [ { "files" => [ { "filename" => "start.png", "content_type" => "image/png" } ] } ], session.args_for("media_upload")
    assert_equal [ [ "https://s3.test/put", 18, "image/png" ] ], @http.puts
    assert_equal [ { "media_ids" => [ "m-1" ], "type" => "image" } ], session.args_for("media_confirm")
  end

  test "submit de vídeo: Kling com mode, resolution e duration explícitos, use_unlim false e start/end" do
    session = FakeMcpSession.new("generate_video_batch" => { "jobs" => [ { "index" => 0, "job_id" => "job-9" } ] })

    job_id = gateway(session).submit(
      model: "kling4_0", prompt: "0-2s: clique", params: { aspect_ratio: "16:9", foo: "ignorado" },
      media: [ { value: "m-1", role: "start_image" }, { value: "job-end", role: "end_image" } ]
    )

    assert_equal "job-9", job_id
    params = session.args_for("generate_video_batch").first["requests"].first["params"]
    assert_equal({ "model" => "kling4_0", "mode" => "image-to-video", "resolution" => "1080p", "duration" => 10,
                   "aspect_ratio" => "16:9", "prompt" => "0-2s: clique", "use_unlim" => false,
                   "medias" => [ { "value" => "m-1", "role" => "start_image" }, { "value" => "job-end", "role" => "end_image" } ] }, params)
  end

  test "submit de imagem: Nano Banana com resolution 2k e thinking_level high" do
    session = FakeMcpSession.new("generate_image_batch" => { "jobs" => [ { "job_id" => "job-1" } ] })

    gateway(session).submit(model: "nano_banana_2_1", prompt: "p", params: { aspect_ratio: "4:5" },
                            media: [ { value: "m-1", role: "image_references" } ])

    params = session.args_for("generate_image_batch").first["requests"].first["params"]
    assert_equal "2k", params["resolution"]
    assert_equal "high", params["thinking_level"]
    assert_equal "4:5", params["aspect_ratio"]
    assert_equal false, params["use_unlim"]
    refute params.key?("mode")
  end

  test "submit recusa modelo, papel ou mídia inválidos antes de chamar a Higgsfield" do
    session = FakeMcpSession.new

    assert_raises(Higgsfield::RequestError, match: /modelo não suportado/) { gateway(session).submit(model: "sora", prompt: "p") }
    assert_raises(Higgsfield::RequestError, match: /papel "start_image" não existe para nano_banana_2_1/) do
      gateway(session).submit(model: "nano_banana_2_1", prompt: "p", media: [ { value: "m", role: "start_image" } ])
    end
    assert_raises(Higgsfield::RequestError, match: /start_image só pode aparecer uma vez/) do
      gateway(session).submit(model: "kling4_0", prompt: "p", media: [ { value: "a", role: "start_image" }, { value: "b", role: "start_image" } ])
    end
    assert_raises(Higgsfield::RequestError, match: /no máximo 14/) do
      gateway(session).submit(model: "nano_banana_2_1", prompt: "p", media: Array.new(15) { { value: "m", role: "image_references" } })
    end
    assert_empty session.calls
  end

  test "submit sem job_id ou com unlim_choice vira erro legível" do
    unlim = FakeMcpSession.new("generate_image_batch" => { "unlim_choice" => { "question" => "?" } })
    assert_raises(Higgsfield::RequestError, match: /usa só créditos/) { gateway(unlim).submit(model: "nano_banana_2_1", prompt: "p") }

    rejected = FakeMcpSession.new("generate_image_batch" => { "jobs" => [], "errors" => [ { "index" => 0, "error" => "prompt bloqueado" } ] })
    assert_raises(Higgsfield::RequestError, match: /não aceitou a geração.*prompt bloqueado/) { gateway(rejected).submit(model: "nano_banana_2_1", prompt: "p") }
  end

  test "status: completed com result_url é done" do
    session = FakeMcpSession.new("jobs_wait" => { "jobs" => [ { "index" => 0, "job_id" => "j", "status" => "completed", "result_url" => "https://cdn.test/r.mp4" } ], "all_terminal" => true })

    status = gateway(session).status("j")

    assert status.done?
    assert_equal "https://cdn.test/r.mp4", status.result_url
    assert_equal [ { "jobs" => [ { "index" => 0, "job_id" => "j" } ], "timeout_seconds" => 0 } ], session.args_for("jobs_wait")
  end

  test "status: terminais de falha com mensagem em português e o motivo da Higgsfield" do
    {
      "canceled" => /cancelada/, "failed" => /não conseguiu gerar.*Motivo: erro do modelo/,
      "nsfw" => /conteúdo impróprio/, "ip_detected" => /propriedade intelectual/
    }.each do |state, message|
      session = FakeMcpSession.new("jobs_wait" => { "jobs" => [ { "job_id" => "j", "status" => state, "error" => (state == "failed" ? "erro do modelo" : nil) } ] })
      status = gateway(session).status("j")

      assert status.failed?, state
      assert_match message, status.error, state
    end
  end

  test "status: em andamento, novo status e lookup_failed retryable continuam; poll_after vem junto" do
    %w[pending queued in_progress ip_detect status_novo].each do |state|
      session = FakeMcpSession.new("jobs_wait" => { "jobs" => [ { "job_id" => "j", "status" => state } ], "poll_after_seconds" => 8 })
      status = gateway(session).status("j")

      assert status.running?, state
      assert_equal 8.0, status.poll_after
    end

    retryable = FakeMcpSession.new("jobs_wait" => { "jobs" => [ { "job_id" => "j", "status" => "lookup_failed", "retryable" => true } ] })
    assert gateway(retryable).status("j").running?

    permanent = FakeMcpSession.new("jobs_wait" => { "jobs" => [ { "job_id" => "j", "status" => "lookup_failed", "retryable" => false } ] })
    assert_match "não encontrou", gateway(permanent).status("j").error
  end

  test "cost usa estimate_*_cost com os mesmos params do submit" do
    session = FakeMcpSession.new("estimate_video_cost" => { "cost" => { "credits" => 37.5 }, "quote_ref" => "q" })

    credits = gateway(session).cost(model: "kling4_0", prompt: "p", params: { aspect_ratio: "16:9" })

    assert_equal 37.5, credits
    params = session.args_for("estimate_video_cost").first["params"]
    assert_equal({ "model" => "kling4_0", "mode" => "image-to-video", "resolution" => "1080p", "duration" => 10, "aspect_ratio" => "16:9", "prompt" => "p" }, params)
  end

  test "balance e download" do
    session = FakeMcpSession.new("balance" => { "credits" => 5734.5, "subscription_plan_type" => "ultra" })

    assert_equal({ credits: 5734.5, plan: "ultra" }, gateway(session).balance)
    assert_equal "x.png", gateway(session).download("https://cdn.test/x.png").filename
    assert_equal [ "https://cdn.test/x.png" ], @http.gets
  end

  private

  def gateway(session) = Higgsfield::McpGateway.new(session: session, http: @http)
end
