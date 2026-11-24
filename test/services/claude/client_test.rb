require "test_helper"

class Claude::ClientTest < ActiveSupport::TestCase
  # SDK de mentira: grava os params e devolve uma mensagem pronta (ou levanta o erro dado).
  class FakeSdk
    Content = Data.define(:type, :text)
    Usage = Data.define(:input_tokens, :output_tokens, :cache_creation_input_tokens, :cache_read_input_tokens)
    StopDetails = Data.define(:explanation)
    Message = Data.define(:content, :model, :stop_reason, :stop_details, :usage)
    Stream = Data.define(:accumulated_message)

    attr_reader :created, :streamed

    def initialize(stop_reason: :end_turn, error: nil, explanation: nil)
      @stop_reason = stop_reason
      @error = error
      @explanation = explanation
      @created = []
      @streamed = []
    end

    def messages = self

    def create(**params)
      raise @error if @error

      @created << params
      message
    end

    def stream(**params)
      raise @error if @error

      @streamed << params
      Stream.new(accumulated_message: message)
    end

    private

    def message
      Message.new(content: [ Content.new(type: :thinking, text: "x"), Content.new(type: :text, text: '{"ok":true}') ],
                  model: "anthropic/claude-opus-5.5", stop_reason: @stop_reason,
                  stop_details: @explanation && StopDetails.new(explanation: @explanation),
                  usage: Usage.new(input_tokens: 100, output_tokens: 20, cache_creation_input_tokens: 80, cache_read_input_tokens: 0))
    end
  end

  SYSTEM = [ { type: "text", text: "sys", cache_control: { type: "ephemeral" } } ].freeze
  MESSAGES = [ { role: "user", content: "oi" } ].freeze
  SCHEMA = { "type" => "object" }.freeze

  test "monta a chamada do OpenRouter: modelo, effort, json_schema, system com cache e fallback" do
    sdk = FakeSdk.new
    response = Claude::Client.new(sdk: sdk).create(system: SYSTEM, messages: MESSAGES, schema: SCHEMA, effort: "medium", max_tokens: 4_000)

    params = sdk.created.first
    assert_equal "anthropic/claude-opus-5.5", params[:model]
    assert_equal 4_000, params[:max_tokens]
    assert_equal SYSTEM, params[:system_]
    assert_equal MESSAGES, params[:messages]
    assert_equal({ effort: :medium, format_: { type: :json_schema, schema: SCHEMA } }, params[:output_config])
    assert_equal({ extra_body: { fallbacks: [ { model: "anthropic/claude-opus-5" } ] } }, params[:request_options])
    refute params.key?(:betas)
    assert_equal '{"ok":true}', response.text
    assert_equal({ input_tokens: 100, output_tokens: 20, cache_creation_input_tokens: 80, cache_read_input_tokens: 0 }, response.usage)
  end

  test "respostas longas vão por streaming" do
    sdk = FakeSdk.new
    Claude::Client.new(sdk: sdk).create(system: SYSTEM, messages: MESSAGES, schema: SCHEMA, effort: "high", max_tokens: 16_000)

    assert_empty sdk.created
    assert_equal 16_000, sdk.streamed.first[:max_tokens]
  end

  test "recusa levanta Repo2Ad::Refused com a explicação" do
    sdk = FakeSdk.new(stop_reason: :refusal, explanation: "conteúdo proibido")

    error = assert_raises(Repo2Ad::Refused) do
      Claude::Client.new(sdk: sdk).create(system: SYSTEM, messages: MESSAGES, schema: SCHEMA, effort: "low", max_tokens: 100)
    end
    assert_equal "conteúdo proibido", error.message
  end

  test "rede, 429 e 5xx viram erro transitório; chave recusada e 400 viram erro com mensagem" do
    url = URI("https://openrouter.ai/api/v1/messages")
    transient = [
      Anthropic::Errors::APIConnectionError.new(url: url),
      Anthropic::Errors::APITimeoutError.new(url: url),
      Anthropic::Errors::RateLimitError.new(url: url, status: 429, headers: {}, body: nil, request: nil, response: nil),
      Anthropic::Errors::InternalServerError.new(url: url, status: 502, headers: {}, body: nil, request: nil, response: nil)
    ]
    transient.each do |error|
      assert_raises(Claude::TransientError, error.class.name) { call_with(error) }
    end

    auth = Anthropic::Errors::AuthenticationError.new(url: url, status: 401, headers: {}, body: nil, request: nil, response: nil)
    assert_raises(Claude::Error, match: /OPENROUTER_API_KEY/) { call_with(auth) }

    bad = Anthropic::Errors::BadRequestError.new(url: url, status: 400, headers: {}, body: nil, request: nil, response: nil, message: "schema inválido")
    error = assert_raises(Claude::Error) { call_with(bad) }
    assert_match "HTTP 400", error.message
    refute_kind_of Claude::TransientError, error
  end

  test "sem chave, erro claro antes de qualquer chamada" do
    error = assert_raises(Claude::Error) do
      Claude::Client.new(api_key: nil).create(system: SYSTEM, messages: MESSAGES, schema: SCHEMA, effort: "low", max_tokens: 100)
    end
    assert_match "OPENROUTER_API_KEY", error.message
  end

  test "o cliente real aponta para o OpenRouter em /api/v1/messages" do
    sdk = Claude::Client.new(api_key: "sk-test-nao-e-real").send(:sdk)

    assert_equal "https://openrouter.ai/api", sdk.base_url.to_s.chomp("/")
  end

  private

  def call_with(error)
    Claude::Client.new(sdk: FakeSdk.new(error: error)).create(system: SYSTEM, messages: MESSAGES, schema: SCHEMA, effort: "low", max_tokens: 100)
  end
end
