require "test_helper"

class RenderStepTest < ActiveSupport::TestCase
  setup do
    project = Project.create!
    @creative = Creative.create!(project: project, group: "image", recipe: "nb_image", status: "proposed")
  end

  test "status começa em pending" do
    assert_equal "pending", RenderStep.new.status
  end

  test "aceita os nomes e tipos da §3.4" do
    RenderStep::NAMES.each do |name|
      assert build(name: name).valid?, "name #{name} deveria ser válido"
    end
    RenderStep::KINDS.each do |kind|
      assert build(kind: kind).valid?, "kind #{kind} deveria ser válido"
    end
  end

  test "rejeita name, kind e status fora da lista" do
    refute build(name: "qualquer").valid?
    refute build(kind: "xyz").valid?
    refute build(status: "abc").valid?
  end

  test "aceita os status do ciclo do job" do
    RenderStep::STATUSES.each do |status|
      assert build(status: status).valid?, "status #{status} deveria ser válido"
    end
  end

  test "exige creative" do
    refute RenderStep.new(name: "main", kind: "compose").valid?
  end

  private

  def build(**attrs)
    RenderStep.new({ creative: @creative, name: "main", kind: "higgsfield", status: "pending" }.merge(attrs))
  end
end
