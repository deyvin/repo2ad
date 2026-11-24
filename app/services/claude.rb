# Raciocínio P1–P5 via OpenRouter com o SDK da Anthropic (decisões 002 e 003).
module Claude
  class Error < StandardError; end
  # Rede, timeout, 429 e 5xx: o job pode tentar de novo.
  class TransientError < Error; end
  # A resposta não passou no schema depois das novas tentativas.
  class InvalidResponse < Error; end
end
