# Fica no lugar do Claude::Client: grava as chamadas e responde, em ordem, com textos (o JSON que o
# modelo devolveria), Hashes (viram JSON) ou exceções. Nenhum teste chama a rede.
class FakeClaude
  FIXTURES = Rails.root.join("test", "fixtures", "claude")

  attr_reader :calls

  def self.fixture(name) = FIXTURES.join("#{name}.json").read

  def initialize(*responses)
    @responses = responses
    @calls = []
  end

  def create(system:, messages:, schema:, effort:, max_tokens:)
    @calls << { system: system, messages: messages, schema: schema, effort: effort, max_tokens: max_tokens }
    response = @responses.shift || raise("FakeClaude sem resposta programada para a chamada #{@calls.size}")
    raise response if response.is_a?(Exception) || (response.is_a?(Class) && response < Exception)

    text = response.is_a?(String) ? response : response.to_json
    Claude::Client::Response.new(text: text, model: "fake/claude", stop_reason: "end_turn",
                                 usage: { input_tokens: 10, output_tokens: 20, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 })
  end
end
