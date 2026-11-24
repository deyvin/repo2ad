require "test_helper"
require_relative "../../support/fake_claude"

class Stages::MenuTest < ActiveSupport::TestCase
  INVENTORY_NAMES = %w[galeria adicionar-peca selecao-look gerar-de-novo videos mobile].freeze

  setup do
    @brief = JSON.parse(FakeClaude.fixture("p1_brief"))
    @angles = JSON.parse(FakeClaude.fixture("p2_angles"))
    @audience = @brief["audiences"].first.merge("source" => "brief")
    @menu = JSON.parse(FakeClaude.fixture("p3_menu"))
    @inventory = INVENTORY_NAMES.map do |name|
      { path: "docs/screenshots/#{name}.png", kind: "screenshot", description: nil, width: 1600, height: 1000 }
    end
  end

  test "system = common.md + p3_menu.md.erb, effort high e 16000 tokens (§5.0)" do
    stage = build(FakeClaude.new)

    assert stage.system_prompt.start_with?("You are part of Repo2Ad")
    assert_includes stage.system_prompt, "propose the menu of ad creatives"
    assert_equal "high", stage.effort
    assert_equal 16_000, stage.max_tokens
  end

  test "resposta válida volta como Hash, em uma chamada" do
    fake = FakeClaude.new(@menu)

    assert_equal @menu, build(fake).call
    assert_equal 1, fake.calls.size
  end

  test "imagem com receita diferente de nb_image volta ao modelo" do
    broken = JSON.parse(FakeClaude.fixture("p3_menu"))
    broken["items"][0]["recipe"] = "kling_magic"
    fake = FakeClaude.new(broken, @menu)

    assert_equal @menu, build(fake).call
    assert_match "image items must use recipe nb_image", fake.calls[1][:messages].last[:content]
  end

  test "vertical fora de 9:16 volta ao modelo" do
    broken = JSON.parse(FakeClaude.fixture("p3_menu"))
    broken["items"][4]["aspect_ratio"] = "16:9"
    fake = FakeClaude.new(broken, @menu)

    build(fake).call

    assert_match "vertical items must use aspect_ratio 9:16", fake.calls[1][:messages].last[:content]
  end

  test "mídia que não está em media_inputs volta ao modelo" do
    broken = JSON.parse(FakeClaude.fixture("p3_menu"))
    broken["items"][7]["media_paths"] = [ "docs/inventado.png" ]
    fake = FakeClaude.new(broken, @menu)

    build(fake).call

    assert_match "is not in media_inputs", fake.calls[1][:messages].last[:content]
  end

  private

  def build(client)
    Stages::Menu.new(brief: @brief, audience: @audience, angles: @angles, media_inventory: @inventory, client: client)
  end
end
