require "test_helper"
require_relative "../support/creative_fixtures"

class ReviewCreativeJobTest < ActiveJob::TestCase
  include CreativeFixtures

  setup do
    @project = create_cabide_project
    @project.update_columns(status: "generating")
    @creative = create_creative(@project, "I1")
    @creative.update!(spec: p4_fixture("I1"), status: "reviewing")
    image = Vips::Image.black(40, 50).new_from_image([ 1, 2, 3 ]).cast(:uchar).copy(interpretation: :srgb).pngsave_buffer
    @creative.result.attach(io: StringIO.new(image), filename: "i1.png", content_type: "image/png")
    @gateway = Higgsfield::FakeGateway.new(credits: 100.0, cost: 2.0)
    Higgsfield::Gateway.current = @gateway
    HiggsfieldConnection.current.save_tokens(access_token: "t")
    @original = ReviewCreativeJob.client_factory
  end

  teardown do
    Higgsfield::Gateway.current = nil
    ReviewCreativeJob.client_factory = @original
  end

  test "approve_with_notes: grava o QA, criativo done e o projeto termina" do
    use_claude(fixture("p5_approve"))

    ReviewCreativeJob.perform_now(@creative)

    @creative.reload
    assert_equal "done", @creative.status
    assert_equal "approve_with_notes", @creative.qa["verdict"]
    assert_equal "done", @project.reload.status
    assert_no_enqueued_jobs only: PromptCreativeJob
  end

  test "aceite §9: texto errado (\"Cabidee\") volta como regenerate, mas é só sugestão: done, nada refeito, nada gasto" do
    @creative.update!(instructions: "seta menor")
    use_claude(fixture("p5_regenerate"))

    ReviewCreativeJob.perform_now(@creative)

    @creative.reload
    assert_equal "done", @creative.status
    assert_equal "regenerate", @creative.qa["verdict"]
    assert_match "Cabidee", @creative.qa["issues"].first["what"]
    assert_equal fixture("p5_regenerate")["fix_instructions"], @creative.qa["fix_instructions"]
    assert_equal [ 0, "seta menor" ], [ @creative.attempts, @creative.instructions ]
    assert_no_enqueued_jobs only: PromptCreativeJob
    # Nem o BalanceGuard (saldo) nem geração; só a estimativa do botão da sugestão, que não gasta.
    assert_empty @gateway.calls.reject { _1.first == :cost }
    assert_equal "done", @project.reload.status
  end

  test "revisão que falha não prende o criativo: done com aviso" do
    use_claude({}, {}, {})

    ReviewCreativeJob.perform_now(@creative)

    @creative.reload
    assert_equal "done", @creative.status
    assert_match "A revisão automática falhou", @creative.error
  end

  test "o projeto só termina quando todos os selecionados terminam" do
    other = create_creative(@project, "H1")
    use_claude(fixture("p5_approve"))

    ReviewCreativeJob.perform_now(@creative)
    assert_equal "generating", @project.reload.status

    other.update!(status: "failed", error: "x")
    assert_equal "done", @project.reload.status
  end

  private

  def fixture(name) = JSON.parse(FakeClaude.fixture(name))

  def use_claude(*responses)
    fake = FakeClaude.new(*responses)
    ReviewCreativeJob.client_factory = -> { fake }
    fake
  end
end
