# §3.5: P1 sobre o snapshot do repositório. Grava project.brief, classifica os media_inputs (kind e description)
# e leva o projeto de analyzing para awaiting_audience. Erro vira failed com mensagem em português.
class AnalyzeProductJob < ApplicationJob
  queue_as :default

  RETRY_ATTEMPTS = 3
  GIVE_UP_MESSAGE = "O serviço de análise não respondeu. Tente de novo em alguns minutos.".freeze

  # Pontos de troca para os testes (fake do OpenRouter).
  class_attribute :client_factory, default: -> { Claude::Client.new }

  def self.fail_project(project_id, message)
    project = Project.find(project_id)
    project.transition_to!("failed", error: message) if project.can_transition_to?("failed")
  end

  def perform(project_id)
    project = Project.find(project_id)
    return unless project.status == "analyzing"

    images, photos = images_for(project)
    brief = Stages::Brief.new(
      meta: repo_meta(project), files: repo_files(project), brand_hints: brand_hints(project),
      images: images.map(&:last), user_photos: photos.map(&:last), client: self.class.client_factory.call
    ).call

    Project.transaction do
      classify_media(brief, (images + photos).to_h { |media, image| [ image.path, media ] })
      project.update!(brief: brief)
      project.transition_to!("awaiting_audience")
    end
  rescue Claude::TransientError, Repo::TransientError
    # Rede, 429 e 5xx: até RETRY_ATTEMPTS execuções no total, contadas por executions, com espera crescente.
    if executions >= RETRY_ATTEMPTS
      self.class.fail_project(project_id, GIVE_UP_MESSAGE)
    else
      retry_job wait: (executions**4 + 2).seconds
    end
  rescue Repo2Ad::Refused => e
    self.class.fail_project(project_id, "A análise foi recusada pelo modelo: #{e.message}")
  rescue Claude::Error, Repo::Error => e
    self.class.fail_project(project_id, e.message)
  rescue StandardError
    self.class.fail_project(project_id, "erro inesperado ao analisar o produto")
    raise
  end

  private

  def root(project)
    path = File.join(IngestRepoJob.repos_dir.to_s, project.id.to_s)
    raise Repo::Error, "Os arquivos do repositório não estão mais disponíveis. Crie o projeto de novo." unless Dir.exist?(path)

    path
  end

  # O ingest não guarda descrição, tópicos e homepage: busca de novo com o mesmo cliente do GitHub.
  def repo_meta(project)
    repo = IngestRepoJob.api_factory.call.repository(owner: project.owner, name: project.name)
    { owner: project.owner, name: project.name, description: repo["description"], topics: Array(repo["topics"]),
      homepage: repo["homepage"], default_branch: repo["default_branch"], sha: project.commit_sha }
  end

  def repo_files(project)
    dir = root(project)
    Repo::Selector.call(dir).text_files.map do |path|
      [ path, File.read(File.join(dir, path), mode: "rb").force_encoding(Encoding::UTF_8).scrub ]
    end
  end

  def brand_hints(project)
    Repo::BrandHints.call(root(project)).to_h
  end

  # [[media_input, Claude::Stage::Image]] do repositório e dos uploads, só com arquivo anexado.
  def images_for(project)
    inputs = project.media_inputs.with_attached_file.order(:id).select { _1.file.attached? }
    pairs = inputs.map do |media|
      path = media.path.presence || "uploads/#{media.id}/#{media.file.filename}"
      [ media, Claude::Stage::Image.new(path: path, width: media.width, height: media.height,
                                        media_type: media.file.content_type, data: media.file.download) ]
    end
    pairs.partition { |media, _| media.source == "repo" }
  end

  def classify_media(brief, by_path)
    Array(brief["media"]).each do |item|
      media = by_path[item["path"]] or next
      media.update!(path: item["path"], kind: item["kind"], description: item["description"])
    end
  end
end
