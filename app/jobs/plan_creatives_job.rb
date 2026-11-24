# §3.5: P3 monta o cardápio de criativos a partir dos ângulos. Grava um Creative por item (proposed; os
# recomendados já vêm marcados) e leva o projeto para awaiting_selection. Erro vira failed com mensagem em português.
class PlanCreativesJob < ApplicationJob
  queue_as :default

  RETRY_ATTEMPTS = 3
  GIVE_UP_MESSAGE = "O serviço de cardápio não respondeu. Tente de novo em alguns minutos.".freeze

  # Pontos de troca para os testes (fake do OpenRouter).
  class_attribute :client_factory, default: -> { Claude::Client.new }

  def self.fail_project(project_id, message)
    project = Project.find(project_id)
    project.transition_to!("failed", error: message) if project.can_transition_to?("failed")
  end

  def perform(project_id)
    project = Project.find(project_id)
    return unless project.status == "planning" && project.angles.present? && project.creatives.none?

    menu = Stages::Menu.new(brief: project.brief, audience: project.audience, angles: project.angles,
                            media_inventory: media_inventory(project), client: self.class.client_factory.call).call

    Project.transaction do
      Array(menu["items"]).each do |item|
        project.creatives.create!(code: item["code"], group: item["group"], recipe: item["recipe"],
                                  aspect_ratio: item["aspect_ratio"], duration: item["duration_seconds"],
                                  title: item["title"], concept: item, selected: item["recommended"] == true)
      end
      project.transition_to!("awaiting_selection")
    end
  rescue Claude::TransientError
    if executions >= RETRY_ATTEMPTS
      self.class.fail_project(project_id, GIVE_UP_MESSAGE)
    else
      retry_job wait: (executions**4 + 2).seconds
    end
  rescue Repo2Ad::Refused => e
    self.class.fail_project(project_id, "O cardápio foi recusado pelo modelo: #{e.message}")
  rescue Claude::Error => e
    self.class.fail_project(project_id, e.message)
  rescue StandardError
    self.class.fail_project(project_id, "erro inesperado ao montar o cardápio")
    raise
  end

  private

  def media_inventory(project)
    project.media_inputs.where.not(path: nil).order(:id).map do |media|
      { path: media.path, kind: media.kind, description: media.description, width: media.width, height: media.height }
    end
  end
end
