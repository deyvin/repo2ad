# §3.5: o usuário escolheu o público. O P2 gera os ângulos (project.angles) e enfileira o P3.
# Erro vira failed com mensagem em português; transitório é tentado de novo, até RETRY_ATTEMPTS execuções.
class BuildAnglesJob < ApplicationJob
  queue_as :default

  RETRY_ATTEMPTS = 3
  GIVE_UP_MESSAGE = "O serviço de ângulos não respondeu. Tente de novo em alguns minutos.".freeze

  # Pontos de troca para os testes (fake do OpenRouter).
  class_attribute :client_factory, default: -> { Claude::Client.new }

  def self.fail_project(project_id, message)
    project = Project.find(project_id)
    project.transition_to!("failed", error: message) if project.can_transition_to?("failed")
  end

  def perform(project_id)
    project = Project.find(project_id)
    return unless project.status == "planning" && project.angles.blank?

    angles = Stages::Angles.new(brief: project.brief, audience: project.audience,
                                client: self.class.client_factory.call).call
    project.update!(angles: angles)
    PlanCreativesJob.perform_later(project.id)
  rescue Claude::TransientError
    if executions >= RETRY_ATTEMPTS
      self.class.fail_project(project_id, GIVE_UP_MESSAGE)
    else
      retry_job wait: (executions**4 + 2).seconds
    end
  rescue Repo2Ad::Refused => e
    self.class.fail_project(project_id, "Os ângulos foram recusados pelo modelo: #{e.message}")
  rescue Claude::Error => e
    self.class.fail_project(project_id, e.message)
  rescue StandardError
    self.class.fail_project(project_id, "erro inesperado ao gerar os ângulos")
    raise
  end
end
