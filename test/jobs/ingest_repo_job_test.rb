require "test_helper"
require "tmpdir"
require_relative "../support/fake_github_api"

class IngestRepoJobTest < ActiveJob::TestCase
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
    project = Project.create!(repo_url: "https://github.com/deyvin/cabide")

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
    project = Project.create!(repo_url: "https://github.com/deyvin/cabide")

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
    project = Project.create!(repo_url: "https://github.com/deyvin/cabide")

    assert_raises(RuntimeError) { IngestRepoJob.perform_now(project.id) }

    project.reload
    assert_equal "failed", project.status
    assert_equal "erro inesperado ao ingerir o repositório", project.error
  end
end
