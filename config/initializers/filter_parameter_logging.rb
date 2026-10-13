# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password, :secret, :_key, :auth, :crypt, :salt, :certificate, :otp, :access, :private, :protected, :ssn,
  :otp_secret, :otp_code, :backup_code, :mfa_token, :otp_backup_codes,
  # CEVICO (auditoria 12/10, achado #176): o JSON da conta de serviço do Google
  # carrega a chave privada — não pode ir para o log ao salvar Integrações
  :service_account_json, :service_account
]

# qualquer parâmetro terminado em "json" (credenciais coladas inteiras) também fica fora do log
Rails.application.config.filter_parameters += [/json\z/i]

# Regex to filter all occurrences of 'token' in keys except for 'website_token'
filter_regex = /\A(?!.*\bwebsite_token\b).*token/i

# Apply the regex for filtering
Rails.application.config.filter_parameters += [filter_regex]
