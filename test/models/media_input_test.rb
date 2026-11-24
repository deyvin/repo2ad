require "test_helper"

class MediaInputTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!
  end

  test "source aceita repo e upload" do
    %w[repo upload].each do |source|
      assert build(source: source).valid?, "source #{source} deveria ser válido"
    end
  end

  test "source fora da lista é inválido" do
    refute build(source: "email").valid?
  end

  test "kind pode ficar vazio antes do P1" do
    assert build(kind: nil).valid?
  end

  test "kind aceita os valores da §3.4" do
    MediaInput::KINDS.each do |kind|
      assert build(kind: kind).valid?, "kind #{kind} deveria ser válido"
    end
  end

  test "kind fora da lista é inválido" do
    refute build(kind: "video").valid?
  end

  private

  def build(**attrs)
    MediaInput.new({ project: @project, source: "repo" }.merge(attrs))
  end
end
