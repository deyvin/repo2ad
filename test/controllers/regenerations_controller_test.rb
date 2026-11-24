require "test_helper"
require_relative "../support/creative_fixtures"

class RegenerationsControllerTest < ActionDispatch::IntegrationTest
  include CreativeFixtures
  include ActiveJob::TestHelper

  setup do
    @project = create_cabide_project
    @project.update_columns(status: "done")
    @creative = create_creative(@project, "I1")
    @creative.update!(spec: p4_fixture("I1"), status: "done", qa: { "verdict" => "approve" }, instructions: "antiga")
    @gateway = Higgsfield::FakeGateway.new(credits: 100.0, cost: 2.0)
    Higgsfield::Gateway.current = @gateway
    HiggsfieldConnection.current.save_tokens(access_token: "t")
  end

  teardown { Higgsfield::Gateway.current = nil }

  test "Gerar de novo: grava a observação, reabre o projeto e recomeça pelo P4" do
    assert_enqueued_with(job: PromptCreativeJob, args: [ @creative ]) do
      post project_creative_regeneration_path(@project, @creative), params: { instructions: "  seta menor  " }
    end

    assert_redirected_to project_path(@project)
    assert_equal "Gerando o I1 de novo.", flash[:notice]
    @creative.reload
    assert_equal [ "queued", "seta menor", nil, nil ], [ @creative.status, @creative.instructions, @creative.qa, @creative.error ]
    assert_equal "generating", @project.reload.status
  end

  test "sem observação, limpa as instruções antigas e gera de novo" do
    post project_creative_regeneration_path(@project, @creative)

    assert_nil @creative.reload.instructions
    assert_equal "queued", @creative.status
  end

  test "criativo ainda em geração não pode ser refeito" do
    @creative.update!(status: "rendering")

    post project_creative_regeneration_path(@project, @creative), params: { instructions: "x" }

    assert_equal "O I1 ainda está sendo gerado.", flash[:alert]
    assert_equal "rendering", @creative.reload.status
    assert_no_enqueued_jobs only: PromptCreativeJob
  end

  test "sem saldo: avisa e não muda nada" do
    @gateway.credits = 0.5

    post project_creative_regeneration_path(@project, @creative), params: { instructions: "x" }

    assert_match "Saldo insuficiente", flash[:alert]
    assert_equal [ "done", "antiga" ], [ @creative.reload.status, @creative.instructions ]
    assert_equal "done", @project.reload.status
    assert_no_enqueued_jobs only: PromptCreativeJob
  end
end
