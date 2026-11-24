require "test_helper"
require_relative "../support/fake_claude"

class BuildAnglesJobTest < ActiveJob::TestCase
  setup do
    @brief = JSON.parse(FakeClaude.fixture("p1_brief"))
    @angles = JSON.parse(FakeClaude.fixture("p2_angles"))
    @audience = @brief["audiences"].first.merge("source" => "brief")
    @original_client = BuildAnglesJob.client_factory
  end

  teardown do
    BuildAnglesJob.client_factory = @original_client
  end

  test "grava os ângulos e enfileira o P3" do
    project = Project.create!(repo_url: "https://github.com/deyvin/cabide", status: "planning",
                              brief: @brief, audience: @audience)
    BuildAnglesJob.client_factory = -> { FakeClaude.new(@angles) }

    assert_enqueued_with(job: PlanCreativesJob, args: [ project.id ]) do
      BuildAnglesJob.perform_now(project.id)
    end

    project.reload
    assert_equal @angles, project.angles
    assert_equal "planning", project.status
  end

  test "fora de planning não chama o modelo" do
    project = Project.create!(repo_url: "https://github.com/deyvin/cabide", status: "awaiting_audience", brief: @brief)
    fake = FakeClaude.new
    BuildAnglesJob.client_factory = -> { fake }

    BuildAnglesJob.perform_now(project.id)

    assert_empty fake.calls
    assert_nil project.reload.angles
  end

  test "erro do modelo marca failed com a mensagem" do
    project = Project.create!(repo_url: "https://github.com/deyvin/cabide", status: "planning",
                              brief: @brief, audience: @audience)
    BuildAnglesJob.client_factory = -> { FakeClaude.new(Claude::InvalidResponse.new("resposta inválida")) }

    BuildAnglesJob.perform_now(project.id)

    project.reload
    assert_equal "failed", project.status
    assert_equal "resposta inválida", project.error
  end
end
