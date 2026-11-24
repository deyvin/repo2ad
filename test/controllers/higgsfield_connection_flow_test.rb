require "test_helper"
require_relative "../support/fake_mcp_session"

class HiggsfieldConnectionFlowTest < ActionDispatch::IntegrationTest
  include SingletonStub

  LOGIN_FAILED_MESSAGE = "O login na Higgsfield não foi concluído. Tente conectar de novo.".freeze

  class LoginSession
    attr_reader :finished_with

    def authorization_url = "https://clerk.higgsfield.test/oauth/authorize?state=abc"
    def finish_login(params) = (@finished_with = params)
  end

  test "desconectado, a tela de novo projeto oferece Conectar Higgsfield" do
    get new_project_path

    assert_select "a[href='#{connect_higgsfield_path}']", "Conectar Higgsfield"
    assert_select "turbo-frame#balance", count: 0
  end

  test "conectado, a tela mostra o saldo num frame preguiçoso e o botão Desconectar" do
    HiggsfieldConnection.current.save_tokens(access_token: "t")

    get new_project_path

    assert_select "turbo-frame#balance[src='#{balance_path}'][loading=lazy]"
    assert_select "button", "Desconectar"
    assert_select "a[href='#{connect_higgsfield_path}']", count: 0
  end

  test "connect manda o navegador para o login da Higgsfield" do
    stub_singleton(Higgsfield::Mcp::Session, :new, LoginSession.new) do
      get connect_higgsfield_path
    end

    assert_redirected_to "https://clerk.higgsfield.test/oauth/authorize?state=abc"
  end

  test "falha ao iniciar o login volta com alerta" do
    failing = Object.new
    def failing.authorization_url = raise(Higgsfield::TransientError, "servidor fora do ar")

    stub_singleton(Higgsfield::Mcp::Session, :new, failing) do
      get connect_higgsfield_path
    end

    assert_redirected_to root_path
    assert_equal LOGIN_FAILED_MESSAGE, flash[:alert]
  end

  test "o callback entrega a query inteira ao fluxo OAuth" do
    login = LoginSession.new
    stub_singleton(Higgsfield::Mcp::Session, :new, login) do
      get higgsfield_callback_path, params: { code: "c0de", state: "abc", iss: "https://clerk.higgsfield.test" }
    end

    assert_redirected_to root_path
    assert_equal({ "code" => "c0de", "state" => "abc", "iss" => "https://clerk.higgsfield.test" }, login.finished_with.to_h)
    assert_equal "Higgsfield conectada.", flash[:notice]
  end

  test "o saldo mostra os créditos" do
    HiggsfieldConnection.current.save_tokens(access_token: "t")
    fake = FakeMcpSession.new("balance" => { "credits" => 2950.5, "subscription_plan_type" => "ultra" })

    stub_singleton(Higgsfield::Mcp::Session, :new, fake) do
      get balance_path
    end

    assert_response :success
    assert_select "turbo-frame#balance", /2\.950,5 créditos/
  end

  test "saldo indisponível não quebra a página" do
    failing = Object.new
    def failing.call(*) = raise(Higgsfield::TransientError, "timeout")

    stub_singleton(Higgsfield::Mcp::Session, :new, failing) do
      get balance_path
    end

    assert_response :success
    assert_select "turbo-frame#balance", /saldo indisponível/
  end

  test "desconectar apaga os tokens" do
    HiggsfieldConnection.current.save_tokens(access_token: "t")

    delete higgsfield_connection_path

    assert_redirected_to root_path
    refute HiggsfieldConnection.current.connected?
  end

  test "callback com erro técnico mostra só a mensagem em português e manda o detalhe para o log" do
    failing = Object.new
    def failing.finish_login(*) = raise(Higgsfield::RequestError, "Authorization callback `state` matches no pending authorization")
    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    begin
      stub_singleton(Higgsfield::Mcp::Session, :new, failing) do
        get higgsfield_callback_path, params: { code: "c0de", state: "abc" }
      end
    ensure
      Rails.logger = original_logger
    end

    assert_redirected_to root_path
    assert_equal LOGIN_FAILED_MESSAGE, flash[:alert]
    refute_includes flash[:alert], "state"
    assert_includes log.string, "matches no pending authorization"
  end

  test "saldo com erro de qualquer classe continua em 200 e mostra indisponível" do
    unexpected = Class.new(StandardError)
    failing = Object.new
    def failing.call(*) = raise(@error_class, "inseguro")
    failing.instance_variable_set(:@error_class, unexpected)

    stub_singleton(Higgsfield::Mcp::Session, :new, failing) do
      get balance_path
    end

    assert_response :success
    assert_select "turbo-frame#balance", /saldo indisponível/
  end

  test "sem chaves de criptografia e com tokens salvos, a página abre e o cabeçalho avisa" do
    HiggsfieldConnection.current.save_tokens(access_token: "t")

    without_encryption_keys do
      get new_project_path
    end

    assert_response :success
    assert_select "h1", "Qual repositório vamos anunciar?"
    assert_select "header", /configure as chaves de criptografia \(\.env\)/
  end

  test "o código de autorização do OAuth não vai para o log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal "[FILTERED]", filter.filter("code" => "c0de-oauth-123456", "state" => "abc")["code"]
    assert_equal "I1", filter.filter("creative" => { "code" => "I1" })["creative"]["code"]
  end

  private

  # Tira as chaves de criptografia só durante o bloco, e devolve tudo ao estado anterior.
  # O contexto guarda o key provider já montado, então ele também é zerado e depois restaurado.
  def without_encryption_keys
    config = ActiveRecord::Encryption.config
    saved_config = [ config.primary_key, config.deterministic_key, config.key_derivation_salt ]
    context = ActiveRecord::Encryption.context
    saved_provider = context.instance_variable_get(:@key_provider)

    config.primary_key = config.deterministic_key = config.key_derivation_salt = nil
    context.instance_variable_set(:@key_provider, nil)
    yield
  ensure
    config.primary_key, config.deterministic_key, config.key_derivation_salt = saved_config
    context.instance_variable_set(:@key_provider, saved_provider)
  end
end
