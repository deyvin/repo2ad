module Higgsfield
  # Gateway sobre o servidor MCP da Higgsfield (decisão 006, adendo do spike):
  # media_upload → PUT pré-assinado → media_confirm; generate_*_batch com um item e use_unlim: false;
  # jobs_wait com timeout_seconds: 0; estimate_*_cost; balance.
  class McpGateway
    include Gateway

    # O padrão do servidor difere das receitas (Kling: text-to-video; Nano Banana: 1k e medium),
    # então mode, resolution e thinking_level vão sempre explícitos.
    DEFAULTS = {
      "nano_banana_2_1" => { resolution: "2k", thinking_level: "high" },
      "kling4_0" => { mode: "image-to-video", resolution: "1080p", duration: 10 }
    }.freeze
    PARAMS = %i[aspect_ratio duration mode resolution thinking_level].freeze
    ROLES = {
      "nano_banana_2_1" => %w[image_references],
      "kling4_0" => %w[start_image end_image image_references]
    }.freeze
    MAX_MEDIA = { "nano_banana_2_1" => 14, "kling4_0" => 10 }.freeze

    RUNNING = %w[pending waiting queued dna script visuals vision flow in_progress ip_detect].freeze
    FAILURES = {
      "canceled" => "A geração foi cancelada na Higgsfield.",
      "failed" => "A Higgsfield não conseguiu gerar o resultado.",
      "nsfw" => "A Higgsfield bloqueou o resultado por conteúdo impróprio (NSFW).",
      "ip_detected" => "A Higgsfield bloqueou o resultado por possível uso de marca ou propriedade intelectual de terceiros."
    }.freeze

    def initialize(session: Mcp::Session.new, http: Http.new)
      @session = session
      @http = http
    end

    def upload(path, content_type: nil)
      path = path.to_s
      content_type ||= Marcel::MimeType.for(Pathname.new(path), name: File.basename(path))
      type = content_type.to_s.split("/").first
      raise RequestError, "tipo de mídia não suportado para upload: #{content_type}" unless type.in?(%w[image video])

      result = @session.call("media_upload", files: [ { filename: File.basename(path), content_type: content_type } ])
      target = Array(hash(result)["uploads"]).first
      raise RequestError, "A Higgsfield não devolveu a URL de upload" unless target&.dig("upload_url") && target["media_id"]

      @http.put(target["upload_url"], File.binread(path), content_type)
      @session.call("media_confirm", media_ids: [ target["media_id"] ], type: type)
      target["media_id"]
    end

    def submit(model:, prompt:, params: {}, media: [])
      request = generation_params(model, prompt, params, media).merge(use_unlim: false)
      result = hash(@session.call(tool_for(model, "generate_%s_batch"), requests: [ { index: 0, params: request } ]))
      job_id = Array(result["jobs"]).first&.dig("job_id")
      return job_id if job_id.present?

      raise RequestError, "A Higgsfield pediu para escolher entre gerações ilimitadas e créditos; o app usa só créditos." if result.key?("unlim_choice")

      detail = (result["errors"] || result["failed"] || result).to_json
      raise RequestError, "A Higgsfield não aceitou a geração: #{detail.truncate(300)}"
    end

    def status(job_id)
      result = hash(@session.call("jobs_wait", jobs: [ { index: 0, job_id: job_id } ], timeout_seconds: 0))
      job = Array(result["jobs"]).first || {}
      poll_after = result["poll_after_seconds"]
      state = job["status"].to_s

      case state
      when "completed"
        return Gateway::Status.new(state: :done, result_url: job["result_url"], error: nil, poll_after: nil) if job["result_url"].present?

        failed("A Higgsfield terminou a geração sem devolver o arquivo.")
      when *FAILURES.keys
        failed([ FAILURES[state], job["error"].presence ].compact.join(" Motivo: "))
      when "lookup_failed"
        return running(poll_after) if job["retryable"]

        failed("A Higgsfield não encontrou a geração #{job_id}.")
      else
        running(poll_after) # RUNNING e qualquer status novo contam como em andamento
      end
    end

    def cost(model:, prompt: nil, params: {}, media: [])
      request = generation_params(model, prompt, params, media)
      result = hash(@session.call(tool_for(model, "estimate_%s_cost"), params: request))
      credits = result.dig("cost", "credits")
      raise RequestError, "A Higgsfield não devolveu o custo estimado" if credits.nil?

      credits.to_f
    end

    def balance
      result = hash(@session.call("balance"))
      { credits: result["credits"]&.to_f, plan: result["subscription_plan_type"] }
    end

    def download(url)
      @http.get(url)
    end

    private

    def generation_params(model, prompt, params, media)
      raise RequestError, "modelo não suportado: #{model.inspect}" unless DEFAULTS.key?(model)

      params = DEFAULTS[model].merge(params.to_h.symbolize_keys.slice(*PARAMS).compact)
      request = { model: model, **params }
      request[:prompt] = prompt if prompt.present?
      medias = normalize_media(model, media)
      request[:medias] = medias if medias.any?
      request
    end

    def normalize_media(model, media)
      items = Array(media).map { |item| item.to_h.symbolize_keys.slice(:value, :role) }
      items.each do |item|
        raise RequestError, "mídia sem value (media_id ou job_id)" if item[:value].blank?
        raise RequestError, "papel #{item[:role].inspect} não existe para #{model} (use #{ROLES[model].join(", ")})" unless item[:role].in?(ROLES[model])
      end
      %w[start_image end_image].each do |role|
        raise RequestError, "#{role} só pode aparecer uma vez" if items.count { _1[:role] == role } > 1
      end
      raise RequestError, "#{model} aceita no máximo #{MAX_MEDIA[model]} imagens" if items.size > MAX_MEDIA[model]

      items
    end

    def tool_for(model, pattern)
      format(pattern, model == "kling4_0" ? "video" : "image")
    end

    def running(poll_after)
      Gateway::Status.new(state: :running, result_url: nil, error: nil, poll_after: poll_after&.to_f)
    end

    def failed(message)
      Gateway::Status.new(state: :failed, result_url: nil, error: message, poll_after: nil)
    end

    def hash(result)
      return result if result.is_a?(Hash)

      raise RequestError, "Resposta inesperada da Higgsfield: #{result.to_s.truncate(200)}"
    end
  end
end
