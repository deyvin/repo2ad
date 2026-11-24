require "test_helper"
require_relative "../support/creative_fixtures"
require_relative "../support/media_fixtures"

class ResultsControllerTest < ActionDispatch::IntegrationTest
  include CreativeFixtures
  include MediaFixtures

  setup do
    Higgsfield::Gateway.current = Higgsfield::FakeGateway.new(cost: 2.0)
    HiggsfieldConnection.current.save_tokens(access_token: "t")
    @project = create_cabide_project
    @project.update_columns(status: "generating")
    @i1 = create_creative(@project, "I1")
    png = Vips::Image.black(40, 50).new_from_image([ 1, 2, 3 ]).cast(:uchar).copy(interpretation: :srgb).pngsave_buffer
    @i1.result.attach(io: StringIO.new(png), filename: "i1.png", content_type: "image/png")
    @i1.update!(status: "done", qa: JSON.parse(FakeClaude.fixture("p5_approve")))
    @h1 = create_creative(@project, "H1")
    @h1.update!(status: "rendering")
    @v3 = create_creative(@project, "V3")
    @v3.update!(status: "failed", error: "O passo main falhou: A Higgsfield bloqueou o resultado por conteúdo impróprio (NSFW).")
  end

  test "grade: imagem pronta com QA e ações, vídeo em geração e criativo com falha" do
    get project_results_path(@project)

    assert_response :success
    assert_select "h1", "Seus criativos"
    assert_select "##{dom_id(@project, :results_summary)}", /1 de 3 prontos, 1 com falha, 1 em andamento/
    assert_select "turbo-cable-stream-source", 1

    assert_select "##{dom_id(@i1, :result)}" do
      assert_select "h2", /I1/
      assert_select "p", "Imagem 4:5"
      assert_select "img[alt^='Criativo I1']"
      assert_select "strong", "Aprovado com ressalvas"
      assert_select "span", "nota 8 de 10"
      assert_select "li", /Os rótulos ANTES e DEPOIS ficaram abaixo das fotos/
      assert_select "a[href*='disposition=attachment']", "Baixar"
      assert_select "dialog form[action='#{project_creative_regeneration_path(@project, @i1)}'] textarea[name='instructions']"
    end

    assert_select "##{dom_id(@h1, :result)}" do
      assert_select "p", "Vídeo horizontal 16:9, 10 s"
      assert_select "p", /Gerando na Higgsfield/
      assert_select "dialog", 0
    end

    assert_select "##{dom_id(@v3, :result)}" do
      assert_select "[role=alert]", /conteúdo impróprio/
      assert_select "a", { text: "Baixar", count: 0 }
      assert_select "button", "Gerar de novo"
    end
  end

  teardown { Higgsfield::Gateway.current = nil }

  test "revisão que pede para refazer vira sugestão: botão com custo e observação preenchida pela correção" do
    @i1.update!(qa: JSON.parse(FakeClaude.fixture("p5_regenerate")))
    fix = @i1.qa["fix_instructions"]

    get project_results_path(@project)

    assert_select "##{dom_id(@i1, :result)}" do
      assert_select "strong", "A revisão sugere gerar de novo"
      assert_select "li", /Cabidee/
      assert_select "button[data-action='dialog#open'][data-dialog-instructions-param=?]", fix, text: "Aceitar sugestão e gerar de novo (≈ 2 créditos)"
      assert_select "button[data-dialog-instructions-param='']", "Gerar de novo"
      assert_select "dialog textarea[data-dialog-target='instructions']"
    end
  end

  test "aprovado com ressalvas não sugere refazer, só mostra as notas" do
    get project_results_path(@project)

    assert_select "##{dom_id(@i1, :result)}" do
      assert_select "strong", "Aprovado com ressalvas"
      assert_select "button", { text: /Aceitar sugestão/, count: 0 }
    end
  end

  test "vídeo pronto vira <video> em loop mudo" do
    video = make_video(Dir.mktmpdir, "h1.mp4", size: "320x180", duration: 1)
    File.open(video, "rb") { @h1.result.attach(io: _1, filename: "h1.mp4", content_type: "video/mp4") }
    @h1.update!(status: "done")

    get project_results_path(@project)

    assert_select "##{dom_id(@h1, :result)} video[autoplay][loop][muted][playsinline]"
  end

  test "sem criativos selecionados mostra o caminho de volta" do
    @project.creatives.update_all(selected: false)

    get project_results_path(@project)

    assert_select "p", /Nenhum criativo foi marcado para gerar ainda/
  end

  test "mudança de status do criativo atualiza o card e o resumo ao vivo" do
    assert_turbo_stream_broadcasts([ @project, :results ], count: 2) do
      @h1.update!(status: "reviewing")
    end
  end
end
