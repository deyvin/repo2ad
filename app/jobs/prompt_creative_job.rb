# §3.5: "Gerar" → P4 para um criativo selecionado. Grava creative.spec e enfileira o RenderCreativeJob.
class PromptCreativeJob < ApplicationJob
  queue_as :default

  RETRY_ATTEMPTS = 3
  GIVE_UP_MESSAGE = "O serviço de IA não respondeu ao preparar este criativo. Tente de novo.".freeze

  class_attribute :client_factory, default: -> { Claude::Client.new }

  def perform(creative)
    return unless creative.status.in?(%w[queued prompting])

    Recipes.for(creative.recipe) # receita ainda não disponível falha antes de gastar uma chamada
    creative.update!(status: "prompting", error: nil)
    spec = Stages::CreativeSpec.new(creative, client: self.class.client_factory.call).call

    creative.transaction do
      creative.render_steps.destroy_all # spec novo, steps novos
      creative.update!(spec: spec, status: "rendering")
    end
    RenderCreativeJob.perform_later(creative)
  rescue Claude::TransientError
    if executions >= RETRY_ATTEMPTS
      fail!(creative, GIVE_UP_MESSAGE)
    else
      retry_job wait: (executions**4 + 2).seconds
    end
  rescue Repo2Ad::Refused => e
    fail!(creative, "O modelo recusou preparar este criativo: #{e.message}")
  rescue Claude::Error, Recipes::Error => e
    fail!(creative, e.message)
  end

  private

  def fail!(creative, message)
    creative.update!(status: "failed", error: message)
  end
end
