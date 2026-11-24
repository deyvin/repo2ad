module Repo
  # Erro que vale nova tentativa: rede, timeout, 5xx, 429 e rate limit do GitHub.
  # retry_after (segundos) vem do Retry-After ou do X-RateLimit-Reset, quando o GitHub informa.
  class TransientError < Error
    attr_reader :retry_after

    def initialize(message = "erro transitório ao falar com o GitHub", retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end
end
