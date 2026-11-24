require "test_helper"
require_relative "../support/fake_claude"

class PlanCreativesJobTest < ActiveJob::TestCase
  INVENTORY_NAMES = %w[galeria adicionar-peca selecao-look gerar-de-novo videos mobile].freeze

  setup do
    @brief = JSON.parse(FakeClaude.fixture("p1_brief"))
    @menu = JSON.parse(FakeClaude.fixture("p3_menu"))
    @original_client = PlanCreativesJob.client_factory
    @project = Project.create!(repo_url: "https://github.com/deyvin/cabide", status: "planning", brief: @brief,
                               audience: @brief["audiences"].first.merge("source" => "brief"),
                               angles: JSON.parse(FakeClaude.fixture("p2_angles")))
    INVENTORY_NAMES.each do |name|
      @project.media_inputs.create!(source: "repo", path: "docs/screenshots/#{name}.png", kind: "screenshot")
    end
  end

  teardown do
    PlanCreativesJob.client_factory = @original_client
  end

  test "monta 10 criativos, marca os recomendados e leva o projeto a awaiting_selection" do
    PlanCreativesJob.client_factory = -> { FakeClaude.new(@menu) }

    PlanCreativesJob.perform_now(@project.id)

    @project.reload
    assert_equal "awaiting_selection", @project.status
    assert_equal 10, @project.creatives.count
    assert_equal %w[H1 I1 V1], @project.creatives.where(selected: true).order(:code).pluck(:code)
    assert_equal "proposed", @project.creatives.find_by(code: "I1").status
    assert_equal "Antes e depois no catálogo", @project.creatives.find_by(code: "I1").title
  end

  test "erro do modelo marca failed com a mensagem" do
    PlanCreativesJob.client_factory = -> { FakeClaude.new(Claude::InvalidResponse.new("cardápio inválido")) }

    PlanCreativesJob.perform_now(@project.id)

    @project.reload
    assert_equal "failed", @project.status
    assert_equal "cardápio inválido", @project.error
    assert_empty @project.creatives
  end
end
