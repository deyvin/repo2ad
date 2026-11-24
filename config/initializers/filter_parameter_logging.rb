# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc, :code_verifier,
  # Código de autorização do OAuth da Higgsfield (callback). Só valores longos: o código de um criativo ("I1") continua visível.
  ->(key, value) { value.replace("[FILTERED]") if key.to_s == "code" && value.is_a?(String) && value.length > 8 }
]
