require "test_helper"
require_relative "../support/fake_mcp_session"

class HiggsfieldConnectionTest < ActiveSupport::TestCase
  test "stores tokens encrypted and reports the connection" do
    connection = HiggsfieldConnection.current
    refute connection.connected?

    connection.save_tokens(access_token: "secret-access", refresh_token: "secret-refresh")

    assert connection.reload.connected?
    assert_equal "secret-access", connection.tokens["access_token"]
    raw = HiggsfieldConnection.connection.select_value("SELECT tokens FROM higgsfield_connections WHERE id = #{connection.id}")
    refute_includes raw, "secret-access"
    assert connection.connected_at.present?
  end

  test "pending authorizations are consumed exactly once" do
    connection = HiggsfieldConnection.current
    connection.save_pending_authorization("state-1", { "code_verifier" => "v", "server_url" => "https://mcp.test/mcp" })

    assert_equal "v", connection.pending_authorization("state-1")["code_verifier"]
    assert_equal "v", connection.delete_pending_authorization("state-1")["code_verifier"]
    assert_nil connection.delete_pending_authorization("state-1")
    assert_nil connection.pending_authorization("state-1")
  end

  test "disconnect forgets the tokens but keeps the client registration" do
    connection = HiggsfieldConnection.current
    connection.save_client_information(client_id: "abc")
    connection.save_tokens(access_token: "t")

    connection.disconnect!

    refute connection.reload.connected?
    assert_equal "abc", connection.client_information["client_id"]
  end
end

class HiggsfieldConnectionTokenLifecycleTest < ActiveSupport::TestCase
  test "pins expires_in to an absolute expiry and survives the JSON round trip" do
    connection = HiggsfieldConnection.current
    freeze_time do
      connection.save_tokens("access_token" => "a", "refresh_token" => "r", "expires_in" => 3600, "issuer" => "https://auth.test")

      tokens = HiggsfieldConnection.find(connection.id).tokens
      assert_equal 3600, tokens["expires_in"]
      assert_equal Time.current.to_i + 3600, tokens["expires_at"]
      assert_equal "https://auth.test", tokens["issuer"]
      assert_equal "r", connection.reload.refresh_token
    end
  end

  test "knows when the access token is about to expire" do
    connection = HiggsfieldConnection.current
    connection.save_tokens(access_token: "a", refresh_token: "r", expires_in: 3600)
    refute connection.access_token_expired?

    travel 59.minutes do
      assert connection.access_token_expired?
    end
  end

  test "tokens without an expiry are trusted until the server refuses them" do
    connection = HiggsfieldConnection.current
    connection.save_tokens(access_token: "a")
    refute connection.access_token_expired?
  end

  test "a wipe for a refresh token another process already rotated keeps the new tokens" do
    connection = HiggsfieldConnection.current
    connection.save_tokens(access_token: "a1", refresh_token: "r1")
    HiggsfieldConnection.find(connection.id).save_tokens(access_token: "a2", refresh_token: "r2") # the other process

    connection.save_tokens(nil) # what the gem does after invalid_grant on r1

    assert connection.reload.connected?
    assert_equal "r2", connection.refresh_token
  end

  test "a wipe for the current refresh token clears the login" do
    connection = HiggsfieldConnection.current
    connection.save_tokens(access_token: "a1", refresh_token: "r1")

    connection.save_tokens(nil)

    refute connection.reload.connected?
    assert_nil connection.connected_at
  end
end
