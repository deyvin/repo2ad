require "test_helper"
require "tmpdir"
require_relative "../support/fake_github_api"
require_relative "../support/fake_claude"

class AnalyzeProductJobTest < ActiveJob::TestCase
  setup do
    @dir = Dir.mktmpdir("analyze-test")
    @original = [ IngestRepoJob.api_factory, IngestRepoJob.repos_dir, AnalyzeProductJob.client_factory ]
    IngestRepoJob.repos_dir = @dir
    IngestRepoJob.api_factory = -> { FakeGithubApi.new }
    @brief = JSON.parse(FakeClaude.fixture("p1_brief"))

    @project = Project.create!(repo_url: "https://github.com/deyvin/cabide")
    IngestRepoJob.perform_now(@project.id) # snapshot real da fixture do Cabide, sem rede
    @project.reload
  end

  teardown do
    IngestRepoJob.api_factory, IngestRepoJob.repos_dir, AnalyzeProductJob.client_factory = @original
    FileUtils.remove_entry(@dir)
  end

  test "grava o brief, classifica as mídias e leva o projeto para awaiting_audience" do
    fake = use_claude(@brief)

    AnalyzeProductJob.perform_now(@project.id)

    @project.reload
    assert_equal "awaiting_audience", @project.status
    assert_equal @brief, @project.brief
    @brief["media"].each do |item|
      media = @project.media_inputs.find_by!(path: item["path"])
      assert_equal item["kind"], media.kind
      assert_equal item["description"], media.description
    end

    texts = fake.calls.first[:messages].first[:content].select { _1[:type] == "text" }.map { _1[:text] }
    assert_match %r{"sha": "#{FakeGithubApi::COMMIT_SHA}"}, texts.first
    assert texts.any? { _1.start_with?(%(<repo_file path="README.md">)) }
    assert texts.any? { _1.start_with?(%(<repo_image path="docs/screenshots/galeria.png")) }
    assert_equal @project.media_inputs.count, fake.calls.first[:messages].first[:content].count { _1[:type] == "image" }
  end

  test "aceite do §9: o brief do Cabide não promete grátis nem download e a CTA honesta é o GitHub" do
    must_not = @brief["must_not_claim"].map { "#{_1["claim"]} #{_1["reason"]}" }.join(" ").downcase
    assert_match(/gr[áa]tis|free/, must_not)
    assert_match(/baix|download/, must_not)

    honest = @brief["cta_options"].select { _1["honest_for_current_status"] }
    assert honest.any? { "#{_1["label"]} #{_1["destination"]}".match?(/github/i) }, "nenhuma CTA honesta aponta para o GitHub"
    refute honest.any? { _1["label"].match?(/baix|download/i) }
  end

  test "resposta inválida três vezes: projeto failed com mensagem em português" do
    use_claude({}, {}, {})

    AnalyzeProductJob.perform_now(@project.id)

    @project.reload
    assert_equal "failed", @project.status
    assert_match "fora do formato esperado", @project.error
  end

  test "recusa do modelo: failed com a explicação" do
    use_claude(Repo2Ad::Refused.new("conteúdo do repositório viola a política"))

    AnalyzeProductJob.perform_now(@project.id)

    assert_equal "failed", @project.reload.status
    assert_match "recusada pelo modelo: conteúdo do repositório viola a política", @project.error
  end

  test "erro transitório agenda nova tentativa e o projeto continua em analyzing" do
    fake = use_claude(Claude::TransientError.new("429"))

    assert_enqueued_with(job: AnalyzeProductJob, args: [ @project.id ]) { AnalyzeProductJob.perform_now(@project.id) }

    assert_equal "analyzing", @project.reload.status
    assert_equal 1, fake.calls.size
  end

  test "na 3ª execução com erro transitório, desiste e falha com mensagem" do
    use_claude(Claude::TransientError.new("timeout"))
    job = AnalyzeProductJob.new(@project.id)
    job.executions = AnalyzeProductJob::RETRY_ATTEMPTS - 1 # perform_now soma 1

    assert_no_enqueued_jobs(only: AnalyzeProductJob) { job.perform_now }

    assert_equal "failed", @project.reload.status
    assert_equal AnalyzeProductJob::GIVE_UP_MESSAGE, @project.error
  end

  test "sem os arquivos extraídos, falha com mensagem clara" do
    use_claude(@brief)
    FileUtils.rm_rf(File.join(@dir, @project.id.to_s))

    AnalyzeProductJob.perform_now(@project.id)

    assert_equal "failed", @project.reload.status
    assert_match "não estão mais disponíveis", @project.error
  end

  test "projeto fora de analyzing não é analisado de novo" do
    fake = use_claude(@brief)
    @project.transition_to!("awaiting_audience")

    AnalyzeProductJob.perform_now(@project.id)

    assert_empty fake.calls
  end

  private

  def use_claude(*responses)
    fake = FakeClaude.new(*responses)
    AnalyzeProductJob.client_factory = -> { fake }
    fake
  end
end
