require "test_helper"
require_relative "../support/fake_claude"

class AudiencesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @brief = JSON.parse(FakeClaude.fixture("p1_brief"))
    @project = Project.create!(repo_url: "https://github.com/deyvin/cabide", status: "awaiting_audience", brief: @brief)
  end

  test "mostra os três públicos do brief e o card Outro" do
    get project_audience_path(@project)

    assert_response :success
    assert_select "input[type=radio][name=audience_choice]", count: 4
    assert_select "input[value=brechos_lojas_online]"
    assert_select "textarea[name=custom_audience]"
    assert_select "span", /Brechós e pequenas lojas/
  end

  test "sem escolha, volta com erro e não muda o projeto" do
    patch project_audience_path(@project)

    assert_response :unprocessable_entity
    assert_select "p[role=alert]", /Escolha um dos públicos/
    assert_equal "awaiting_audience", @project.reload.status
  end

  test "escolher um público do brief grava o público, leva a planning e enfileira os ângulos" do
    assert_enqueued_with(job: BuildAnglesJob, args: [ @project.id ]) do
      patch project_audience_path(@project), params: { audience_choice: "marcas_autorais_merch" }
    end

    assert_response :see_other
    @project.reload
    assert_equal "planning", @project.status
    assert_equal "marcas_autorais_merch", @project.audience["key"]
    assert_equal "brief", @project.audience["source"]
  end

  test "Outro público exige texto e grava o texto" do
    patch project_audience_path(@project), params: { audience_choice: "outro", custom_audience: "  " }
    assert_response :unprocessable_entity

    patch project_audience_path(@project), params: { audience_choice: "outro", custom_audience: "Donas de ateliê" }

    assert_equal({ "source" => "custom", "description" => "Donas de ateliê" }, @project.reload.audience)
  end

  test "depois da escolha, a tela mostra o público e os ângulos prontos" do
    @project.update!(audience: @brief["audiences"].first.merge("source" => "brief"))
    @project.transition_to!("planning")
    @project.update!(angles: JSON.parse(FakeClaude.fixture("p2_angles")))

    get project_audience_path(@project)

    assert_response :success
    assert_select "h1", /Brechós e pequenas lojas/
    assert_select "li", 4
    assert_select "span", "Principal"
    assert_select "li", /Foto do chão vira catálogo/
  end

  test "em planning sem ângulos ainda, a tela avisa que estão sendo gerados" do
    @project.update!(audience: @brief["audiences"].first.merge("source" => "brief"))
    @project.transition_to!("planning")

    get project_audience_path(@project)

    assert_select "p", "Gerando ângulos de mensagem…"
  end
end
