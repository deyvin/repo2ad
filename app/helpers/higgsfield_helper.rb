module HiggsfieldHelper
  # Estado da conexão para o cabeçalho. Chave de criptografia ausente ou trocada não derruba a página: vira um aviso.
  def higgsfield_connection_state
    HiggsfieldConnection.current.connected? ? :connected : :disconnected
  rescue ActiveRecord::Encryption::Errors::Base => e
    Rails.logger.error("[repo2ad] higgsfield: não consegui ler os tokens (#{e.class}): #{e.message}")
    :encryption_error
  end
end
