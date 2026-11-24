require "test_helper"
require_relative "../../support/creative_fixtures"

class Stages::CreativeSpecTest < ActiveSupport::TestCase
  include CreativeFixtures

  setup do
    @project = create_cabide_project
    @i1 = create_creative(@project, "I1")
    @h1 = create_creative(@project, "H1")
  end

  test "system + contrato da receita + exemplos aprovados, todos cacheáveis; effort high e 16000 tokens" do
    fake = FakeClaude.new(p4_fixture("H1"))
    Stages::CreativeSpec.new(@h1, client: fake).call

    system = fake.calls.first[:system]
    assert_equal 3, system.size
    assert system.all? { _1[:cache_control] == { type: "ephemeral" } }
    assert_includes system[0][:text], "Your job: turn one menu item into the exact generation spec"
    assert_includes system[1][:text], "### 6.4 `kling_keyframes`"
    assert_includes system[2][:text], "### 12.1 I1"
    assert_includes system[2][:text], "### 12.3 H1"
    assert_equal [ "high", 16_000 ], [ fake.calls.first[:effort], fake.calls.first[:max_tokens] ]
  end

  test "kling_magic leva os contratos da kling_reference e da kling_magic (decisão 008)" do
    @h1.update!(recipe: "kling_magic")
    blocks = Stages::CreativeSpec.new(@h1).send(:fixed_blocks)

    assert_includes blocks.first, "### 6.2 `kling_reference`"
    assert_includes blocks.first, "### 6.3 `kling_magic`"
  end

  test "conteúdo: brief, ângulo, item, inventário de mídia, imagens do item e instruções do usuário" do
    @i1.update!(instructions: "seta menor")
    content = Stages::CreativeSpec.new(@i1).user_content
    texts = content.select { _1[:type] == "text" }.map { _1[:text] }

    assert texts[0].start_with?("<brief>\n{")
    assert_includes texts[1], %("key": "antes_depois")
    assert_includes texts[2], %("code": "I1")
    assert_includes texts[3], %("path": "docs/screenshots/galeria.png")
    assert_includes texts, %(<user_photo path="uploads/chao.jpg" width="900" height="1200"/>)
    assert_includes texts, %(<user_photo path="uploads/catalogo.png" width="1024" height="1024"/>)
    assert_equal 2, content.count { _1[:type] == "image" }
    assert_equal "<user_instructions>\nseta menor\n</user_instructions>", texts.last
  end

  test "os specs do I1 e do H1 (§12) passam no schema e nas regras extras" do
    assert_empty Stages::CreativeSpec.new(@i1).validation_errors(p4_fixture("I1"))
    assert_empty Stages::CreativeSpec.new(@h1).validation_errors(p4_fixture("H1"))
  end

  test "regras do §5.5 e da receita" do
    cases = {
      "compose com model" => [ ->(s) { s["steps"][0]["model"] = "nano_banana_2_1" }, "compose needs model null" ],
      "nano com outro modelo" => [ ->(s) { s["steps"][1]["model"] = "kling4_0" }, %(nano_banana needs model "nano_banana_2_1") ],
      "kling sem start_image" => [ ->(s) { s["steps"][2]["inputs"]["start_image"] = nil }, "kling needs a start_image" ],
      "start_image em outro aspecto" => [
        ->(s) { s["steps"][0]["params"]["aspect_ratio"] = "9:16"; s["steps"][0]["compose_plan"]["canvas_aspect"] = "9:16" },
        "start image is 9:16 but params.aspect_ratio is 16:9"
      ],
      "step:<nome> para frente" => [ ->(s) { s["steps"][1]["inputs"]["image_references"] = [ "step:main" ] }, "step:main must refer to an earlier step" ],
      "mídia inventada" => [ ->(s) { s["steps"][1]["inputs"]["image_references"] = [ "nao/existe.png" ] }, %(media "nao/existe.png" does not exist) ],
      "moldura phone" => [ ->(s) { s["steps"][0]["compose_plan"]["layers"][0]["frame"] = "phone" }, "phone is not supported yet" ],
      "ordem da receita" => [ ->(s) { s["steps"].rotate! }, "this recipe needs exactly start_frame:compose, end_frame:nano_banana, main:kling" ],
      "receita diferente" => [ ->(s) { s["recipe"] = "kling_reference" }, %(/recipe: must be "kling_keyframes") ],
      "duração do item" => [ ->(s) { s["steps"][2]["params"]["duration"] = 5 }, "must be the item's 10" ]
    }
    stage = Stages::CreativeSpec.new(@h1)
    cases.each do |name, (mutate, message)|
      spec = p4_fixture("H1")
      mutate.call(spec)
      assert_includes stage.validation_errors(spec).join("\n"), message, name
    end
  end
end
