require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  NON_FAILED = (Project::STATUSES - %w[failed]).freeze

  test "novo projeto começa em draft" do
    assert_equal "draft", Project.new.status
  end

  test "caminho feliz do draft ao done" do
    project = Project.create!

    %w[ingesting analyzing awaiting_audience planning awaiting_selection generating done].each do |status|
      project.transition_to!(status)
      assert_equal status, project.reload.status
    end
  end

  test "transições fora do fluxo levantam InvalidTransition e não mudam o status" do
    NON_FAILED.each do |from|
      (NON_FAILED - Project::NEXT_STATUSES[from]).each do |to|
        project = Project.create!(status: from)

        assert_raises(Project::InvalidTransition, "#{from} -> #{to} deveria ser inválida") do
          project.transition_to!(to)
        end
        assert_equal from, project.reload.status
      end
    end
  end

  test "qualquer status que não seja failed pode ir para failed com error" do
    NON_FAILED.each do |from|
      project = Project.create!(status: from)

      project.transition_to!("failed", error: "falhou em #{from}")

      project.reload
      assert_equal "failed", project.status, "de #{from}"
      assert_equal "falhou em #{from}", project.error, "de #{from}"
    end
  end

  test "failed é terminal: não vai para nenhum status, nem para failed de novo" do
    project = Project.create!(status: "failed", error: "boom")

    Project::STATUSES.each do |to|
      assert_raises(Project::InvalidTransition, "failed -> #{to} deveria ser inválida") do
        project.transition_to!(to, error: "de novo")
      end
    end
    assert_equal "boom", project.reload.error
  end

  test "ir para failed exige error" do
    project = Project.create!(status: "analyzing")

    assert_raises(ArgumentError) { project.transition_to!("failed") }
    assert_raises(ArgumentError) { project.transition_to!("failed", error: "  ") }
    assert_equal "analyzing", project.reload.status
  end

  test "can_transition_to? responde sem alterar o projeto" do
    project = Project.create!(status: "awaiting_audience")

    assert project.can_transition_to?("planning")
    assert project.can_transition_to?("failed")
    refute project.can_transition_to?("generating")
    assert_equal "awaiting_audience", project.reload.status
  end

  test "status fora da lista é inválido" do
    project = Project.new(status: "pausado")

    refute project.valid?
    assert project.errors.of_kind?(:status, :inclusion)
  end

  test "failed sem error é inválido" do
    project = Project.new(status: "failed")

    refute project.valid?
    assert project.errors.of_kind?(:error, :blank)
  end

  test "update! não pula o fluxo: draft não vai direto para done" do
    project = Project.create!

    assert_raises(ActiveRecord::RecordInvalid) { project.update!(status: "done") }
    assert_equal "draft", project.reload.status
  end

  test "update! não tira um projeto de failed" do
    project = Project.create!(status: "failed", error: "x")

    assert_raises(ActiveRecord::RecordInvalid) { project.update!(status: "ingesting", error: nil) }

    project.reload
    assert_equal "failed", project.status
    assert_equal "x", project.error
  end

  test "update! aceita transições do fluxo e failed com error" do
    project = Project.create!
    project.update!(status: "ingesting")
    project.update!(status: "failed", error: "boom")

    assert_equal "failed", project.reload.status
    assert_equal "boom", project.error
  end

  test "criação pode começar em qualquer status válido" do
    assert Project.create!(status: "done").persisted?
  end

  test "transition_to! aceita símbolo" do
    project = Project.create!

    project.transition_to!(:ingesting)
    assert_equal "ingesting", project.reload.status

    project.transition_to!(:failed, error: "x")
    assert_equal "failed", project.reload.status
  end
end
