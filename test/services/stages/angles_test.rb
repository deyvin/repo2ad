require "test_helper"
require_relative "../../support/fake_claude"

class Stages::AnglesTest < ActiveSupport::TestCase
  setup do
    @brief = JSON.parse(FakeClaude.fixture("p1_brief"))
    @audience = @brief["audiences"].first.merge("source" => "brief")
    @angles = JSON.parse(FakeClaude.fixture("p2_angles"))
  end

  test "system = common.md + p2_angles.md.erb, effort medium e 8000 tokens (§5.0)" do
    stage = build(FakeClaude.new)

    assert stage.system_prompt.start_with?("You are part of Repo2Ad")
    assert_includes stage.system_prompt, "Your job: given the product brief and ONE chosen audience"
    assert_equal "medium", stage.effort
    assert_equal 8_000, stage.max_tokens
  end

  test "conteúdo: brief e público escolhido em blocos de texto" do
    texts = build(FakeClaude.new).user_content.map { _1[:text] }

    assert_match %r{\A<brief>\n\{}, texts[0]
    assert_match %r{\A<audience>\n\{.*"key": "brechos_lojas_online"}m, texts[1]
  end

  test "resposta válida volta como Hash, em uma chamada" do
    fake = FakeClaude.new(@angles)

    assert_equal @angles, build(fake).call
    assert_equal 1, fake.calls.size
  end

  test "dois ângulos principais voltam ao modelo com o erro" do
    broken = JSON.parse(FakeClaude.fixture("p2_angles"))
    broken["angles"][1]["primary"] = true
    fake = FakeClaude.new(broken, @angles)

    assert_equal @angles, build(fake).call
    assert_equal 2, fake.calls.size
    assert_match "exactly one angle must be primary", fake.calls[1][:messages].last[:content]
  end

  private

  def build(client)
    Stages::Angles.new(brief: @brief, audience: @audience, client: client)
  end
end
