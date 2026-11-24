require "test_helper"

class BalanceGuardTest < ActiveSupport::TestCase
  test "sem conexão com a Higgsfield, não gera e diz para conectar" do
    error = assert_raises(Higgsfield::BalanceGuard::NotConnected) do
      Higgsfield::BalanceGuard.check!(2, gateway: Higgsfield::FakeGateway.new, connection: HiggsfieldConnection.current)
    end

    assert_equal "Conecte a Higgsfield para gerar", error.message
  end

  test "com saldo igual ou maior, não levanta erro" do
    gateway = Higgsfield::FakeGateway.new(credits: 39.5)

    assert_nothing_raised do
      Higgsfield::BalanceGuard.check!(39.5, gateway: gateway, connection: connected_connection)
    end
  end

  test "saldo insuficiente diz quanto precisa e quanto tem, em português" do
    gateway = Higgsfield::FakeGateway.new(credits: 10.0)

    error = assert_raises(Higgsfield::BalanceGuard::Insufficient) do
      Higgsfield::BalanceGuard.check!(39.5, gateway: gateway, connection: connected_connection)
    end

    assert_equal "Saldo insuficiente: precisa de 39,50 créditos, você tem 10,00", error.message
  end

  test "saldo que não pode ser lido vira erro claro" do
    gateway = Higgsfield::FakeGateway.new(credits: nil)

    error = assert_raises(Higgsfield::Error) do
      Higgsfield::BalanceGuard.check!(2, gateway: gateway, connection: connected_connection)
    end

    assert_equal "Não consegui ler o saldo da Higgsfield.", error.message
  end

  private

  def connected_connection
    connection = HiggsfieldConnection.current
    connection.save_tokens(access_token: "token-de-teste")
    connection
  end
end
