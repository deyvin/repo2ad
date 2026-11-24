require "test_helper"
require "tmpdir"
require_relative "../support/fake_github_api"

# API de mentira que falha ao consultar o repositório. Recebe um erro por chamada; a última se repete. Sem rede.
class FailingGithubApi
  def initialize(*errors)
    @errors = errors
  end

  def repository(**)
    raise(@errors.size > 1 ? @errors.shift : @errors.first)
  end
end

class IngestRepoJobTest < ActiveJob::TestCase
  CABIDE_URL = "https://github.com/deyvin/cabide".freeze

  setup do
    @dir = Dir.mktmpdir("ingest-test")
    @original_api = IngestRepoJob.api_factory
    @original_dir = IngestRepoJob.repos_dir
    IngestRepoJob.repos_dir = @dir
  end

  teardown do
    IngestRepoJob.api_factory = @original_api
    IngestRepoJob.repos_dir = @original_dir
    FileUtils.remove_entry(@dir)
  end

  test "com o Cabide: cria os media_inputs com imagem anexada e enfileira o P1" do
    IngestRepoJob.api_factory = -> { FakeGithubApi.new }
    project = Project.create!(repo_url: CABIDE_URL)

    assert_enqueued_with(job: AnalyzeProductJob, args: [ project.id ]) do
      IngestRepoJob.perform_now(project.id)
    end

    project.reload
    assert_equal "analyzing", project.status
    assert_equal [ "deyvin", "cabide" ], [ project.owner, project.name ]
    assert_equal FakeGithubApi::COMMIT_SHA, project.commit_sha

    media = project.media_inputs.order(:path).to_a
    screenshots = Dir.glob("docs/screenshots/*.png", base: File.join(@dir, project.id.to_s))
    assert_empty screenshots - media.map(&:path)
    assert_operator media.size, :<=, Repo::Selector::MAX_IMAGES
    assert(media.all? { |m| m.source == "repo" && m.file.attached? && m.file.blob.byte_size.positive? })
    assert(media.all? { |m| [ m.width, m.height ].max <= IngestRepoJob::MAX_IMAGE_SIDE })
  end

  test "URL inválida marca o projeto como failed com mensagem em português" do
    project = Project.create!(repo_url: "https://gitlab.com/deyvin/cabide")

    IngestRepoJob.perform_now(project.id)

    project.reload
    assert_equal "failed", project.status
    assert_match "GitHub", project.error
    assert_empty project.media_inputs
  end

  test "tarball corrompido marca failed e não cria mídia nem enfileira o P1" do
    path = File.join(@dir, "lixo.tar.gz")
    File.write(path, "não é gzip")
    IngestRepoJob.api_factory = -> { FakeGithubApi.new(tarball: path) }
    project = Project.create!(repo_url: CABIDE_URL)

    assert_no_enqueued_jobs do
      IngestRepoJob.perform_now(project.id)
    end

    project.reload
    assert_equal "failed", project.status
    assert_match "corrompido", project.error
    assert_empty project.media_inputs
  end

  test "erro inesperado marca failed com mensagem genérica e relança" do
    IngestRepoJob.api_factory = -> { raise "boom" }
    project = Project.create!(repo_url: CABIDE_URL)

    assert_raises(RuntimeError) { IngestRepoJob.perform_now(project.id) }

    project.reload
    assert_equal "failed", project.status
    assert_equal "erro inesperado ao ingerir o repositório", project.error
  end

  test "erro transitório reagenda o job e mantém o projeto em ingesting" do
    IngestRepoJob.api_factory = -> { FailingGithubApi.new(Repo::TransientError.new("rede")) }
    project = Project.create!(repo_url: CABIDE_URL)

    assert_enqueued_with(job: IngestRepoJob, args: [ project.id ]) do
      IngestRepoJob.perform_now(project.id)
    end

    project.reload
    assert_equal "ingesting", project.status
    assert_empty project.media_inputs
  end

  test "Retry-After do GitHub vira o tempo de espera do reagendamento" do
    IngestRepoJob.api_factory = -> { FailingGithubApi.new(Repo::TransientError.new("limite", retry_after: 120)) }
    project = Project.create!(repo_url: CABIDE_URL)
    before = Time.now.to_f

    IngestRepoJob.perform_now(project.id)

    scheduled = enqueued_jobs.last
    assert_equal IngestRepoJob.name, scheduled[:job].name
    assert_in_delta before + 120, scheduled[:at], 5
  end

  test "esgotadas as tentativas, vai para failed com a mensagem para o usuário" do
    IngestRepoJob.api_factory = -> { FailingGithubApi.new(Repo::TransientError.new("rede")) }
    project = Project.create!(repo_url: CABIDE_URL)
    job = IngestRepoJob.new(project.id)

    # Cada perform_now é uma tentativa do mesmo job; a última esgota o retry_on.
    IngestRepoJob::RETRY_ATTEMPTS.times { job.perform_now }

    project.reload
    assert_equal "failed", project.status
    assert_equal "O GitHub não respondeu. Tente de novo em alguns minutos.", project.error
  end

  test "Retry-After não passa do limite de tentativas" do
    IngestRepoJob.api_factory = -> { FailingGithubApi.new(Repo::TransientError.new("limite", retry_after: 60)) }
    project = Project.create!(repo_url: CABIDE_URL)
    job = IngestRepoJob.new(project.id)

    (IngestRepoJob::RETRY_ATTEMPTS - 1).times { job.perform_now }
    assert_equal "ingesting", project.reload.status

    job.perform_now

    assert_equal "failed", project.reload.status
  end

  test "o limite de 3 tentativas é total, mesmo misturando Retry-After e backoff" do
    IngestRepoJob.api_factory = lambda do
      FailingGithubApi.new(Repo::TransientError.new("limite", retry_after: 60),
                           Repo::TransientError.new("rede"),
                           Repo::TransientError.new("limite", retry_after: 30))
    end
    project = Project.create!(repo_url: CABIDE_URL)
    job = IngestRepoJob.new(project.id)

    job.perform_now
    job.perform_now
    assert_equal "ingesting", project.reload.status

    job.perform_now
    assert_equal "failed", project.reload.status
    assert_equal "O GitHub não respondeu. Tente de novo em alguns minutos.", project.error
  end

  test "404 ou repositório privado não é transitório: failed direto, sem reagendar" do
    IngestRepoJob.api_factory = -> { FailingGithubApi.new(Repo::Error.new("repositório não encontrado")) }
    project = Project.create!(repo_url: CABIDE_URL)

    assert_no_enqueued_jobs { IngestRepoJob.perform_now(project.id) }

    project.reload
    assert_equal "failed", project.status
    assert_match "não encontrado", project.error
  end

  test "nova tentativa apaga o que a anterior deixou e não duplica mídia" do
    project = Project.create!(repo_url: CABIDE_URL, status: "ingesting")
    project.media_inputs.create!(source: "repo", path: "docs/screenshots/galeria.png", width: 1, height: 1)
    leftover = File.join(@dir, project.id.to_s, "lixo")
    FileUtils.mkdir_p(leftover)
    File.write(File.join(leftover, "velho.txt"), "resto")
    IngestRepoJob.api_factory = -> { FakeGithubApi.new }

    IngestRepoJob.perform_now(project.id)

    project.reload
    assert_equal "analyzing", project.status
    paths = project.media_inputs.pluck(:path)
    assert_equal paths.uniq, paths
    assert(project.media_inputs.all? { |m| m.width != 1 })
    refute File.exist?(leftover)
  end
end
