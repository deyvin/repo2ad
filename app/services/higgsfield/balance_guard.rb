module Higgsfield
  # Trava antes de gerar (T13): sem conexão, ou sem créditos para o que vai ser gasto, não gera.
  class BalanceGuard
    class NotConnected < Higgsfield::Error; end
    class Insufficient < Higgsfield::Error; end

    def self.check!(credits_needed, gateway: Higgsfield::Gateway.current, connection: HiggsfieldConnection.current)
      raise ArgumentError, "estimativa de custo inválida" if credits_needed.nil? || credits_needed.to_f.negative?
      raise NotConnected, "Conecte a Higgsfield para gerar" unless connection.connected?

      available = gateway.balance[:credits]
      raise Higgsfield::Error, "Não consegui ler o saldo da Higgsfield." if available.nil?
      return if available.to_f >= credits_needed.to_f

      raise Insufficient, "Saldo insuficiente: precisa de #{format_credits(credits_needed)} créditos, " \
                          "você tem #{format_credits(available)}"
    end

    # Mesmo formato do cabeçalho: milhar com ponto, decimal com vírgula ("3.120,25", "2.950,5").
    def self.format_credits(value)
      ActiveSupport::NumberHelper.number_to_rounded(value.to_f, precision: 2, delimiter: ".", separator: ",",
                                                                strip_insignificant_zeros: true)
    end
  end
end
