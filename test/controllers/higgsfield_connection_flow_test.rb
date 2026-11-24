require "test_helper"
require_relative "../support/fake_mcp_session"

class HiggsfieldConnectionFlowTest < ActionDispatch::IntegrationTest
  include SingletonStub

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
    assert_match "Não foi possível iniciar o login", flash[:alert]
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

  test "o código de autorização do OAuth não vai para o log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal "[FILTERED]", filter.filter("code" => "c0de-oauth-123456", "state" => "abc")["code"]
    assert_equal "I1", filter.filter("creative" => { "code" => "I1" })["creative"]["code"]
  end
end
