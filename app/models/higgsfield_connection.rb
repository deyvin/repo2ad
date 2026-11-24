# The single OAuth connection to the Higgsfield MCP server (this MVP has one user).
#
# Doubles as the token storage the `mcp` gem's OAuth provider expects:
# tokens, client registration and the pending PKCE authorization between
# /higgsfield/connect and /higgsfield/callback.
class HiggsfieldConnection < ApplicationRecord
  serialize :client_information, coder: JSON
  serialize :tokens, coder: JSON
  serialize :pending, coder: JSON

  encrypts :tokens

  # Renew the access token this long before the server would reject it.
  EXPIRY_MARGIN = 2.minutes

  def self.current
    first || create!
  end

  def connected?
    tokens.is_a?(Hash) && (tokens["access_token"].present? || tokens["refresh_token"].present?)
  end

  def refresh_token
    tokens["refresh_token"].presence if tokens.is_a?(Hash)
  end

  # True when the stored access token is (about to be) past its `expires_in`.
  # Tokens saved without an expiry are trusted until the server says otherwise.
  def access_token_expired?(margin: EXPIRY_MARGIN)
    expires_at = tokens["expires_at"] if tokens.is_a?(Hash)
    expires_at.present? && Time.at(expires_at.to_i) <= margin.from_now
  end

  # Forgets the login on purpose (the user asked, or the refresh token is dead).
  # Transient failures must not land here: they would throw away a refresh
  # token that still works.
  def disconnect!
    update!(tokens: nil, pending: nil, connected_at: nil)
  end

  # Drops authorizations a background call started but no browser will finish.
  def discard_pending_authorizations!
    update!(pending: nil) if pending.present?
  end

  # --- storage interface used by MCP::Client::OAuth::Provider ---------------

  def save_tokens(new_tokens)
    new_tokens = with_expiry(new_tokens&.deep_stringify_keys)
    refresh_token_in_use = refresh_token
    with_lock do # reloads: another process may have rotated the tokens meanwhile
      # The gem wipes the tokens when the server rejects the refresh token it
      # sent. If another process already swapped that token for a new one
      # (Clerk rotates them), the rejected token was just stale: keep the new ones.
      next if new_tokens.nil? && refresh_token_in_use && refresh_token && refresh_token != refresh_token_in_use

      update!(tokens: new_tokens, connected_at: (new_tokens ? (connected_at || Time.current) : nil))
    end
  end

  def save_client_information(info)
    update!(client_information: info&.deep_stringify_keys)
  end

  def save_pending_authorization(state, entry)
    with_lock do
      update!(pending: (pending || {}).merge(state => entry.as_json))
    end
  end

  def pending_authorization(state)
    reload.pending&.dig(state)
  end

  # Returns the removed entry so only one callback can redeem a given state.
  def delete_pending_authorization(state)
    with_lock do
      entries = pending || {}
      removed = entries.delete(state)
      update!(pending: entries.presence)
      removed
    end
  end

  private

  # `expires_in` is relative to the moment the token was issued; pin it down.
  def with_expiry(new_tokens)
    return new_tokens unless new_tokens.is_a?(Hash) && new_tokens["expires_in"].to_i.positive?

    new_tokens.merge("expires_at" => Time.current.to_i + new_tokens["expires_in"].to_i)
  end
end
