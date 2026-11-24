require "test_helper"
require "tempfile"
require "turbo/broadcastable/test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  CABIDE_URL = "https://github.com/deyvin/cabide".freeze

  test "new mostra o formulário, a dropzone e o cabeçalho da Higgsfield" do
    get new_project_path

    assert_response :success
    assert_select "h1", "Qual repositório vamos anunciar?"
    assert_select "input[name='project[repo_url]']"
    assert_select "input[type=file][name='project[photos][]'][multiple]"
    assert_select "[data-controller=dropzone]"
    assert_select "a", "Conectar Higgsfield"
  end

  test "root vai para o formulário" do
    get root_path

    assert_response :success
    assert_select "h1", "Qual repositório vamos anunciar?"
  end

  test "URL válida cria o projeto em draft, enfileira a ingestão e leva à tela de análise" do
    assert_enqueued_with(job: IngestRepoJob) do
      post projects_path, params: { project: { repo_url: CABIDE_URL } }
    end

    project = Project.last
    assert_redirected_to project_path(project)
    assert_equal [ "draft", CABIDE_URL ], [ project.status, project.repo_url ]
  end

  test "URL inválida volta ao formulário com erro inline em português e não cria projeto" do
    assert_no_difference "Project.count" do
      post projects_path, params: { project: { repo_url: "https://gitlab.com/deyvin/cabide" } }
    end

    assert_response :unprocessable_entity
    assert_select "p[role=alert]#repo_url_error", /GitHub/
    assert_select "input[name='project[repo_url]'][aria-invalid=true][value=?]", "https://gitlab.com/deyvin/cabide"
  end

  test "mais de 8 fotos é recusado" do
    photos = Array.new(9) { fixture_file_upload("galeria.png", "image/png") }

    assert_no_difference "Project.count" do
      post projects_path, params: { project: { repo_url: CABIDE_URL, photos: photos } }
    end

    assert_response :unprocessable_entity
    assert_select "p[role=alert]", /até 8 fotos/
  end

  test "arquivo fora de JPG, PNG e HEIC é recusado" do
    file = Tempfile.new([ "notas", ".txt" ])
    file.write("oi")
    file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, "text/plain", original_filename: "notas.txt")

    assert_no_difference "Project.count" do
      post projects_path, params: { project: { repo_url: CABIDE_URL, photos: [ upload ] } }
    end

    assert_response :unprocessable_entity
    assert_select "p[role=alert]", /use JPG, PNG ou HEIC/
  ensure
    file&.close!
  end

  test "fotos válidas viram media_inputs de origem upload, guardadas sem normalizar no request" do
    photos = [ fixture_file_upload("galeria.png", "image/png"), fixture_file_upload("sample.heic", "image/heic") ]

    post projects_path, params: { project: { repo_url: CABIDE_URL, photos: photos } }

    project = Project.last
    assert_equal %w[upload upload], project.media_inputs.order(:id).pluck(:source)
    assert(project.media_inputs.all? { |media| media.file.attached? && media.width.nil? })
  end

  test "tela de análise mostra a linha do tempo e se inscreve nas atualizações" do
    project = Project.create!(repo_url: CABIDE_URL)

    get project_path(project)

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(project, :timeline)}"
    assert_select "[aria-current=step]", /baixando repo/
    assert_select "turbo-cable-stream-source"
  end

  test "em analyzing mostra o placeholder de análise" do
    project = Project.create!(repo_url: CABIDE_URL, status: "analyzing")

    get project_path(project)

    assert_select "p", "Analisando produto…"
    assert_select "[aria-current=step]", /analisando produto/
  end

  test "em failed mostra o erro e o link para tentar com outra URL" do
    project = Project.create!(repo_url: CABIDE_URL, status: "failed", error: "O GitHub não respondeu.")

    get project_path(project)

    assert_select "[role=alert]", /O GitHub não respondeu/
    assert_select "a[href=?]", new_project_path, "Tentar com outra URL"
    assert_select "[aria-current=step]", 0
  end

  test "mudar o status atualiza a linha do tempo por Turbo Stream" do
    project = Project.create!(repo_url: CABIDE_URL)

    assert_turbo_stream_broadcasts [ project ] do
      project.transition_to!("ingesting")
    end
  end
end
