# Acompanha um render_step submetido à Higgsfield (§3.5): consulta o status a cada poll_after_seconds
# (padrão 5 s), por no máximo 30 min, baixa o resultado e anexa em render_step.output.
# Ao terminar, devolve a vez ao RenderCreativeJob (próximo step ou resultado final); ao falhar, falha o criativo.
class PollRenderStepJob < ApplicationJob
  queue_as :default

  INTERVAL = 5.seconds
  MAX_INTERVAL = 60.seconds
  TIMEOUT = 30.minutes
  ACTIVE = %w[submitted running].freeze

  retry_on Higgsfield::TransientError, wait: :polynomially_longer, attempts: 8 do |job, error|
    job.send(:fail_step, job.arguments.first, "Falha de rede repetida ao consultar a Higgsfield: #{error.message}")
  end
  discard_on ActiveRecord::RecordNotFound, ActiveJob::DeserializationError

  # deadline: até quando continuar consultando (viaja junto nas próximas execuções).
  def perform(render_step, deadline = nil)
    return unless render_step.status.in?(ACTIVE) && render_step.hf_job_id.present?

    deadline = deadline ? Time.zone.parse(deadline.to_s) : TIMEOUT.from_now
    if Time.current > deadline
      return fail_step(render_step, "A Higgsfield demorou mais de #{TIMEOUT.in_minutes.to_i} minutos para gerar. Tente de novo.")
    end

    gateway = Higgsfield::Gateway.current
    result = gateway.status(render_step.hf_job_id)
    render_step.increment!(:poll_attempts)

    if result.done?
      attach_output(render_step, gateway.download(result.result_url))
      render_step.update!(status: "done", error: nil)
      RenderCreativeJob.perform_later(render_step.creative)
    elsif result.failed?
      fail_step(render_step, result.error)
    else
      render_step.update!(status: "running") unless render_step.status == "running"
      self.class.set(wait: interval(result.poll_after)).perform_later(render_step, deadline.iso8601)
    end
  rescue Higgsfield::RequestError, Higgsfield::ConfigurationError => e
    fail_step(render_step, e.message)
  end

  private

  def interval(poll_after)
    return INTERVAL unless poll_after.to_f.positive?

    poll_after.to_f.seconds.clamp(1.second, MAX_INTERVAL)
  end

  def attach_output(render_step, download)
    extension = File.extname(download.filename).presence || Rack::Mime::MIME_TYPES.invert[download.content_type] || ""
    render_step.output.attach(io: download.io, filename: "#{render_step.name}-#{render_step.id}#{extension}",
                              content_type: download.content_type)
  ensure
    download&.io&.close
  end

  def fail_step(render_step, message)
    Rails.logger.warn("[repo2ad] render_step #{render_step.id} falhou: #{message}")
    render_step.update!(status: "failed", error: message)
    render_step.creative.update!(status: "failed", error: "O passo #{render_step.name} falhou: #{message}")
  end
end
