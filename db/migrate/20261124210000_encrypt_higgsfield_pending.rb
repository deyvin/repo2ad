# O pending (code_verifier do PKCE de logins em andamento) passa a ser criptografado.
# O que está salvo hoje em texto puro é só resto de autorizações antigas: apaga só o pending,
# sem tocar em tokens nem em client_information (o usuário continua conectado).
class EncryptHiggsfieldPending < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE higgsfield_connections SET pending = NULL"
  end

  def down
    execute "UPDATE higgsfield_connections SET pending = NULL"
  end
end
