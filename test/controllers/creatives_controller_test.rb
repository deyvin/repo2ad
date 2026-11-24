require "test_helper"
require_relative "../support/fake_claude"

class CreativesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # FakeGateway cuja estimativa de custo falha, como quando a Higgsfield não responde.
  class FailingCostGateway < Higgsfield::FakeGateway
    def cost(**)
      raise Higgsfield::RequestError, "A Higgsfield não respondeu"
    end
  end

  setup do
    @brief = JSON.parse(FakeClaude.fixture("p1_brief"))
    @project = Project.create!(repo_url: "https://github.com/deyvin/cabide", status: "awaiting_selection",
                               brief: @brief, audience: @brief["audiences"].first.merge("source" => "brief"),
                               angles: JSON.parse(FakeClaude.fixture("p2_angles")))
    @image = @project.creatives.create!(code: "I1", group: "image", recipe: "nb_image", aspect_ratio: "4:5",
                                        title: "Antes e depois", concept: { "concept" => "Foto do chão e catálogo" },
                                        selected: true)
    @video = @project.creatives.create!(code: "V1", group: "vertical", recipe: "kling_reference", aspect_ratio: "9:16",
                                        duration: 10, title: "Look no celular", concept: { "concept" => "Pessoa vestindo" },
                                        selected: false)
  end

  teardown do
    Higgsfield::Gateway.current = nil
  end

  test "mostra o cardápio em grupos, o painel de promessas e o botão Gerar" do
    get project_creatives_path(@project)

    assert_response :success
    assert_select "h1", "Escolha os criativos"
    assert_select "input[type=checkbox][name='creative_ids[]']", count: 2
    assert_select "input[type=checkbox][value=?][checked]", @image.id.to_s
    assert_select "h2", "Imagens"
    assert_select "h2", "Vídeos verticais 9:16"
    assert_select "li", /Grátis \/ sem custo/
    assert_select "input[type=submit][value^=Gerar]"
  end

  test "cada card mostra os créditos estimados e o botão Gerar mostra o total dos marcados" do
    get project_creatives_path(@project)

    assert_select "input[type=checkbox][value=?][data-credits=?]", @image.id.to_s, "2.0"
    assert_select "input[type=checkbox][value=?][data-credits=?]", @video.id.to_s, "4.0"
    assert_select "span", /≈ 2 créditos/
    assert_select "input[type=submit][value=?]", "Gerar (≈ 2 créditos)"
  end

  test "sem estimativa (Higgsfield fora do ar), o card avisa e o botão diz só Gerar" do
    Higgsfield::Gateway.current = FailingCostGateway.new

    get project_creatives_path(@project)

    assert_response :success
    assert_select "span", /estimativa indisponível/
    assert_select "input[type=submit][value=?]", "Gerar"
  end

  test "generating redireciona para os resultados" do
    @project.update!(status: "generating")

    get project_creatives_path(@project)

    assert_redirected_to project_results_path(@project)
  end

  test "Gerar sem nenhum criativo marcado volta com aviso e não muda nada" do
    post project_creatives_path(@project), params: { creative_ids: [] }

    assert_redirected_to project_creatives_path(@project)
    assert_equal "Escolha pelo menos um criativo.", flash[:alert]
    assert_equal "awaiting_selection", @project.reload.status
  end

  test "Gerar com saldo suficiente leva a generating, enfileira um P4 por criativo e vai para os resultados" do
    Higgsfield::Gateway.current = Higgsfield::FakeGateway.new(credits: 100.0, cost: 2.0)
    HiggsfieldConnection.current.save_tokens(access_token: "token-de-teste")

    assert_enqueued_jobs 2, only: PromptCreativeJob do
      post project_creatives_path(@project), params: { creative_ids: [ @image.id, @video.id ] }
    end

    assert_redirected_to project_results_path(@project)
    @project.reload
    assert_equal "generating", @project.status
    assert_equal %w[queued queued], @project.creatives.order(:code).pluck(:status)
  end

  test "saldo insuficiente não gera e não muda os criativos" do
    Higgsfield::Gateway.current = Higgsfield::FakeGateway.new(credits: 1.0, cost: 2.0)
    HiggsfieldConnection.current.save_tokens(access_token: "token-de-teste")

    assert_no_enqueued_jobs only: PromptCreativeJob do
      post project_creatives_path(@project), params: { creative_ids: [ @image.id ] }
    end

    assert_match "Saldo insuficiente", flash[:alert]
    assert_equal "awaiting_selection", @project.reload.status
    assert_equal 0, @project.creatives.where(status: "queued").count
    assert @project.creatives.find_by(code: "I1").selected
  end

  test "sem conexão com a Higgsfield não gera e diz para conectar" do
    Higgsfield::Gateway.current = Higgsfield::FakeGateway.new(credits: 100.0, cost: 2.0)

    post project_creatives_path(@project), params: { creative_ids: [ @image.id ] }

    assert_equal "Conecte a Higgsfield para gerar", flash[:alert]
    assert_equal "awaiting_selection", @project.reload.status
  end
end
