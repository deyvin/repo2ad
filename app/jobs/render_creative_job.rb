# §3.5: executa a receita do criativo, um step por vez. É chamado de novo pelo PollRenderStepJob a cada step
# remoto que termina, até o resultado final ir para creative.result.
class RenderCreativeJob < ApplicationJob
  queue_as :default

  RETRY_ATTEMPTS = 5
  discard_on ActiveRecord::RecordNotFound, ActiveJob::DeserializationError

  def perform(creative)
    return unless creative.status == "rendering"

    Recipes.for(creative.recipe).new(creative).advance!
  rescue Higgsfield::TransientError => e
    if executions >= RETRY_ATTEMPTS
      creative.update!(status: "failed", error: "Falha de rede repetida ao falar com a Higgsfield: #{e.message}")
    else
      retry_job wait: (executions**4 + 2).seconds
    end
  rescue Recipes::Error, Higgsfield::Error => e
    creative.update!(status: "failed", error: e.message)
  end
end
