# §3.5: P5 sobre o resultado. Grava o QA e o criativo vai para done em qualquer veredito.
# "regenerate" é só uma SUGESTÃO para o usuário (decisão do usuário): nada é refeito nem enfileirado
# aqui, e nenhum crédito é gasto. O usuário aceita pela tela de resultado (Gerar de novo).
class ReviewCreativeJob < ApplicationJob
  queue_as :default

  RETRY_ATTEMPTS = 3

  class_attribute :client_factory, default: -> { Claude::Client.new }

  def perform(creative)
    return unless creative.status == "reviewing"

    qa = Stages::Review.new(creative, client: self.class.client_factory.call).call
    creative.update!(qa: qa, status: "done", error: nil)
  rescue Claude::TransientError
    if executions >= RETRY_ATTEMPTS
      finish_without_review(creative, "A revisão automática não respondeu; confira o resultado manualmente.")
    else
      retry_job wait: (executions**4 + 2).seconds
    end
  rescue Repo2Ad::Refused, Claude::Error => e
    finish_without_review(creative, "A revisão automática falhou (#{e.message}); confira o resultado manualmente.")
  end

  private

  def finish_without_review(creative, message)
    creative.update!(status: "done", error: message)
  end
end
