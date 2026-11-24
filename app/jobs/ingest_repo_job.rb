require "fileutils"

# §3.5: ao criar o projeto, baixa o repositório (Fetcher), escolhe o que vai para o P1 (Selector),
# normaliza as imagens e cria os media_inputs (source repo). Ao fim, enfileira o AnalyzeProductJob.
class IngestRepoJob < ApplicationJob
  MAX_IMAGE_SIDE = 1568
  RETRY_ATTEMPTS = 3
  GIVE_UP_MESSAGE = "O GitHub não respondeu. Tente de novo em alguns minutos.".freeze

  # Pontos de troca para os testes: cliente do GitHub (fake) e diretório de extração (temporário).
  class_attribute :api_factory, default: -> { Repo::GithubApi.new }
  class_attribute :repos_dir, default: Rails.root.join("tmp", "repos")

  queue_as :default

  # Erro transitório: nova tentativa com backoff. Esgotadas as tentativas, o projeto vai para failed.
  retry_on Repo::TransientError, wait: :polynomially_longer, attempts: RETRY_ATTEMPTS do |job, _error|
    IngestRepoJob.fail_project(job.arguments.first, GIVE_UP_MESSAGE)
  end

  def self.fail_project(project_id, message)
    project = Project.find(project_id)
    project.transition_to!("failed", error: message) if project.can_transition_to?("failed")
  end

  def perform(project_id)
    project = Project.find(project_id)
    start_ingest(project)

    fetched = Repo::Fetcher.call(project.repo_url, project_id: project.id,
                                                   api: self.class.api_factory.call, base_dir: self.class.repos_dir)
    project.update!(owner: fetched.owner, name: fetched.name, commit_sha: fetched.commit_sha)

    Repo::Selector.call(fetched.root).images.each do |image|
      create_media_input(project, fetched.root, image)
    end

    project.transition_to!("analyzing")
    AnalyzeProductJob.perform_later(project.id)
  rescue Repo::TransientError => e
    # Sem Retry-After, o retry_on faz o backoff e conta as tentativas.
    raise unless e.retry_after

    # Com Retry-After (ou X-RateLimit-Reset), agenda para quando o GitHub liberar. O limite é o mesmo
    # (executions), porque o retry_on não conta essas tentativas.
    if executions < RETRY_ATTEMPTS
      retry_job wait: e.retry_after
    else
      self.class.fail_project(project_id, GIVE_UP_MESSAGE)
    end
  rescue Repo::Error, Media::Probe::Error, Media::Normalizer::Error => e
    self.class.fail_project(project_id, e.message)
  rescue StandardError
    self.class.fail_project(project_id, "erro inesperado ao ingerir o repositório")
    raise
  end

  private

  # Nova tentativa começa do zero: o projeto já pode estar em ingesting, e a pasta e as mídias
  # deixadas pela tentativa anterior saem antes, para não duplicar nada.
  def start_ingest(project)
    project.transition_to!("ingesting") if project.status == "draft"
    project.media_inputs.where(source: "repo").destroy_all
    FileUtils.rm_rf(File.join(self.class.repos_dir.to_s, project.id.to_s))
  end

  def create_media_input(project, root, image)
    normalized = Media::Normalizer.call(File.join(root, image.path), max_side: MAX_IMAGE_SIDE)
    begin
      probe = Media::Probe.call(normalized)
      media = project.media_inputs.create!(source: "repo", path: image.path, width: probe.width, height: probe.height)
      filename = "#{File.basename(image.path, '.*')}#{File.extname(normalized)}"
      File.open(normalized, "rb") { |io| media.file.attach(io: io, filename: filename) }
    ensure
      FileUtils.rm_f(normalized)
    end
  end
end
