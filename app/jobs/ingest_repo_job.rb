require "fileutils"

# §3.5: ao criar o projeto, baixa o repositório (Fetcher), escolhe o que vai para o P1 (Selector),
# normaliza as imagens e cria os media_inputs (source repo). Ao fim, enfileira o AnalyzeProductJob.
class IngestRepoJob < ApplicationJob
  MAX_IMAGE_SIDE = 1568

  # Pontos de troca para os testes: cliente do GitHub (fake) e diretório de extração (temporário).
  class_attribute :api_factory, default: -> { Repo::GithubApi.new }
  class_attribute :repos_dir, default: Rails.root.join("tmp", "repos")

  queue_as :default

  def perform(project_id)
    project = Project.find(project_id)
    project.transition_to!("ingesting")

    fetched = Repo::Fetcher.call(project.repo_url, project_id: project.id,
                                                   api: self.class.api_factory.call, base_dir: self.class.repos_dir)
    project.update!(owner: fetched.owner, name: fetched.name, commit_sha: fetched.commit_sha)

    Repo::Selector.call(fetched.root).images.each do |image|
      create_media_input(project, fetched.root, image)
    end

    project.transition_to!("analyzing")
    AnalyzeProductJob.perform_later(project.id)
  rescue Repo::Error, Media::Probe::Error, Media::Normalizer::Error => e
    fail_project(project_id, e.message)
  rescue StandardError
    fail_project(project_id, "erro inesperado ao ingerir o repositório")
    raise
  end

  private

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

  def fail_project(project_id, message)
    project = Project.find(project_id)
    project.transition_to!("failed", error: message) if project.can_transition_to?("failed")
  end
end
