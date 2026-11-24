module Higgsfield
  # Trava antes de gerar (T13): sem conexão, ou sem créditos para o que vai ser gasto, não gera.
  class BalanceGuard
    class NotConnected < Higgsfield::Error; end
    class Insufficient < Higgsfield::Error; end

    def self.check!(credits_needed, gateway: Higgsfield::Gateway.current, connection: HiggsfieldConnection.current)
      raise NotConnected, "Conecte a Higgsfield para gerar" unless connection.connected?

      available = gateway.balance[:credits]
      raise Higgsfield::Error, "Não consegui ler o saldo da Higgsfield." if available.nil?
      return if available.to_f >= credits_needed.to_f

      raise Insufficient, "Saldo insuficiente: precisa de #{credits(credits_needed)} créditos, você tem #{credits(available)}"
    end

    def self.credits(value)
      format("%.2f", value.to_f).tr(".", ",")
    end
  end
end
