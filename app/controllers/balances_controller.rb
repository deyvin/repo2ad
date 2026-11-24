# Saldo de créditos da Higgsfield no topo, carregado num Turbo Frame preguiçoso:
# uma chamada lenta ou com erro ao MCP nunca trava a página.
class BalancesController < ApplicationController
  CACHE_KEY = "higgsfield/balance".freeze

  def show
    @balance = Rails.cache.fetch(CACHE_KEY, expires_in: 1.minute) do
      result = Higgsfield::Mcp::Session.new.call("balance")
      result.is_a?(Hash) ? result.slice("credits", "subscription_plan_type") : nil
    end
  rescue Higgsfield::Error => e
    Rails.logger.warn("[repo2ad] balance unavailable: #{e.message}")
    @balance = nil
  ensure
    render layout: false
  end
end
