module Stages
  # P2, ângulos de mensagem (§5.3): 4 a 6 ângulos para o público escolhido, um marcado como principal.
  #
  #   Stages::Angles.new(brief: project.brief, audience: project.audience, client: client).call
  class Angles < Claude::Stage
    STAGE = "p2_angles".freeze

    def initialize(brief:, audience:, client: Claude::Client.new)
      super(client: client)
      @brief = brief
      @audience = audience
    end

    def user_content
      [
        text_block("<brief>\n#{JSON.pretty_generate(@brief)}\n</brief>"),
        text_block("<audience>\n#{JSON.pretty_generate(@audience)}\n</audience>")
      ]
    end

    private

    # O schema não garante um único ângulo principal: confere aqui, e a resposta volta ao modelo se falhar.
    def extra_errors(data)
      return [] unless data.is_a?(Hash) && data["angles"].is_a?(Array)

      primaries = data["angles"].count { |angle| angle.is_a?(Hash) && angle["primary"] == true }
      primaries == 1 ? [] : [ "/angles: exactly one angle must be primary (found #{primaries})" ]
    end
  end
end
