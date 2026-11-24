require "anthropic"

module Claude
  # Uma chamada de Messages no OpenRouter (formato Anthropic), com saída em JSON Schema (decisão 002):
  # POST https://openrouter.ai/api/v1/messages, modelo anthropic/claude-opus-5.5, fallback anthropic/claude-opus-5.
  #
  #   Claude::Client.new.create(system: [...], messages: [...], schema: {...}, effort: "high", max_tokens: 16_000)
  #   # => Claude::Client::Response(text:, model:, stop_reason:, usage:)
  class Client
    BASE_URL = "https://openrouter.ai/api".freeze
    MODEL = "anthropic/claude-opus-5.5".freeze
    FALLBACKS = [ { model: "anthropic/claude-opus-5" } ].freeze
    STREAM_FROM_MAX_TOKENS = 8_000 # respostas longas (P1, P3, P4) vão por streaming

    Response = Data.define(:text, :model, :stop_reason, :usage)

    def initialize(api_key: ENV["OPENROUTER_API_KEY"], max_retries: 2, sdk: nil)
      @sdk = sdk
      @api_key = api_key
      @max_retries = max_retries
    end

    def create(system:, messages:, schema:, effort:, max_tokens:)
      params = {
        model: MODEL,
        max_tokens: max_tokens,
        system_: system,
        messages: messages,
        output_config: { effort: effort.to_sym, format_: { type: :json_schema, schema: schema } },
        request_options: { extra_body: { fallbacks: FALLBACKS } }
      }
      message = max_tokens >= STREAM_FROM_MAX_TOKENS ? sdk.messages.stream(**params).accumulated_message : sdk.messages.create(**params)

      if message.stop_reason.to_s == "refusal"
        raise Repo2Ad::Refused, message.stop_details&.explanation.presence || "O modelo recusou esta etapa."
      end

      text = message.content.select { _1.type.to_s == "text" }.map(&:text).join
      Response.new(text: text, model: message.model.to_s, stop_reason: message.stop_reason.to_s, usage: usage(message.usage))
    rescue Anthropic::Errors::APIConnectionError, Anthropic::Errors::RateLimitError, Anthropic::Errors::InternalServerError => e
      raise TransientError, "Falha temporária ao falar com o OpenRouter (#{e.class.name.demodulize}). Tente de novo."
    rescue Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError, Anthropic::Errors::PaymentRequiredError => e
      raise Error, "O OpenRouter recusou a chave ou o saldo (#{e.class.name.demodulize}). Confira a OPENROUTER_API_KEY no .env."
    rescue Anthropic::Errors::APIStatusError => e
      raise Error, "O OpenRouter recusou a chamada (HTTP #{e.status}): #{e.message.to_s.truncate(300)}"
    end

    private

    def sdk
      @sdk ||= begin
        raise Error, "Falta a OPENROUTER_API_KEY no .env." if @api_key.blank?

        Anthropic::Client.new(auth_token: @api_key, base_url: BASE_URL, max_retries: @max_retries)
      end
    end

    def usage(usage)
      return {} unless usage

      %i[input_tokens output_tokens cache_creation_input_tokens cache_read_input_tokens].index_with do |key|
        usage.respond_to?(key) ? usage.public_send(key).to_i : 0
      end
    end
  end
end
