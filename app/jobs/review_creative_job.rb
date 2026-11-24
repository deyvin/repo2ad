# §3.5: P5 sobre o resultado. approve/approve_with_notes → done. regenerate com attempts < 2 → refaz pelo P4
# com o fix_instructions do QA nas instruções (se houver saldo). regenerate com attempts >= 2 → done com o QA
# visível, e o humano decide.
class ReviewCreativeJob < ApplicationJob
  queue_as :default

  MAX_AUTO_REGENERATIONS = 2
  RETRY_ATTEMPTS = 3

  class_attribute :client_factory, default: -> { Claude::Client.new }

  def perform(creative)
    return unless creative.status == "reviewing"

    qa = Stages::Review.new(creative, client: self.class.client_factory.call).call
    creative.update!(qa: qa)

    if qa["verdict"] == "regenerate" && creative.attempts < MAX_AUTO_REGENERATIONS
      regenerate(creative, qa)
    else
      creative.update!(status: "done", error: nil)
    end
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

  # Toda regeneração gasta créditos: confere o saldo antes (Costs::Estimator + BalanceGuard).
  def regenerate(creative, qa)
    Higgsfield::BalanceGuard.check!(Costs::Estimator.for(creative).total)

    attempt = creative.attempts + 1
    note = "QA (regeneração automática #{attempt}): #{qa["fix_instructions"]}"
    creative.update!(attempts: attempt, status: "queued", error: nil,
                     instructions: [ creative.instructions.presence, note ].compact.join("\n"))
    PromptCreativeJob.perform_later(creative)
  rescue Higgsfield::Error => e
    creative.update!(status: "done", error: "O QA pediu para gerar de novo, mas a regeneração automática parou: #{e.message}")
  end

  def finish_without_review(creative, message)
    creative.update!(status: "done", error: message)
  end
end
