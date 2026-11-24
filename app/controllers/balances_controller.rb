# Saldo de créditos da Higgsfield no topo, carregado num Turbo Frame preguiçoso:
# qualquer falha (MCP, rede, criptografia, o que for) vira "saldo indisponível" com HTTP 200 e log.
class BalancesController < ApplicationController
  CACHE_KEY = "higgsfield/balance".freeze

  def show
    @balance = Rails.cache.fetch(CACHE_KEY, expires_in: 1.minute) do
      result = Higgsfield::Mcp::Session.new.call("balance")
      result.is_a?(Hash) ? result.slice("credits", "subscription_plan_type") : nil
    end
  rescue StandardError => e
    Rails.logger.warn("[repo2ad] balance unavailable: #{e.class}: #{e.message}")
    @balance = nil
  ensure
    render layout: false
  end
end
