# Integração com a Higgsfield via servidor MCP oficial, com login OAuth no app (decisão 006).
module Higgsfield
  def self.config
    Rails.application.config_for(:higgsfield)
  end

  class Error < StandardError; end
  class ConfigurationError < Error; end
  # Respostas que tentar de novo não resolve.
  class RequestError < Error
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end
  # Falhas de rede e 5xx: pode tentar de novo.
  class TransientError < Error; end
end
