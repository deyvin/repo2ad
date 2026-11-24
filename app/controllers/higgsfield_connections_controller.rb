# Login no servidor MCP da Higgsfield pelo navegador (OAuth 2.1 + PKCE, registro dinâmico de cliente).
# O detalhe técnico de cada falha vai só para o log; o usuário vê a mensagem em português.
class HiggsfieldConnectionsController < ApplicationController
  LOGIN_FAILED = "O login na Higgsfield não foi concluído. Tente conectar de novo.".freeze

  # GET /higgsfield/connect
  def new
    redirect_to Higgsfield::Mcp::Session.new.authorization_url, allow_other_host: true
  rescue StandardError => e
    Rails.logger.error("[repo2ad] higgsfield connect failed: #{e.class}: #{e.message}")
    redirect_to root_path, alert: LOGIN_FAILED
  end

  # GET /higgsfield/callback
  def callback
    Higgsfield::Mcp::Session.new.finish_login(request.query_parameters)
    Rails.cache.delete(BalancesController::CACHE_KEY)
    redirect_to root_path, notice: "Higgsfield conectada."
  rescue StandardError => e
    Rails.logger.error("[repo2ad] higgsfield callback failed: #{e.class}: #{e.message}")
    redirect_to root_path, alert: LOGIN_FAILED
  end

  # DELETE /higgsfield/connection
  def destroy
    HiggsfieldConnection.current.disconnect!
    Rails.cache.delete(BalancesController::CACHE_KEY)
    redirect_to root_path, notice: "Higgsfield desconectada."
  end
end
