require "test_helper"

class CreativeTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!
  end

  test "group aceita image, vertical e horizontal" do
    Creative::GROUPS.each do |group|
      assert build(group: group).valid?, "group #{group} deveria ser válido"
    end
  end

  test "group fora da lista é inválido" do
    refute build(group: "carrossel").valid?
  end

  test "recipe aceita as quatro receitas da §3.4" do
    %w[nb_image kling_reference kling_keyframes kling_magic].each do |recipe|
      assert build(recipe: recipe).valid?, "recipe #{recipe} deveria ser válido"
    end
  end

  test "recipe fora da lista é inválido" do
    refute build(recipe: "kling_outro").valid?
  end

  test "status começa em proposed e aceita os status da §3.4" do
    assert_equal "proposed", Creative.new.status

    Creative::STATUSES.each do |status|
      assert build(status: status).valid?, "status #{status} deveria ser válido"
    end
  end

  test "status fora da lista é inválido" do
    refute build(status: "pronto").valid?
  end

  private

  def build(**attrs)
    Creative.new({ project: @project, group: "image", recipe: "nb_image", status: "proposed" }.merge(attrs))
  end
end
