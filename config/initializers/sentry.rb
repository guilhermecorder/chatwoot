if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.enabled_environments = %w[staging production]

    # To activate performance monitoring, set one of these options.
    # We recommend adjusting the value in production:
    config.traces_sample_rate = 0.1 if ENV['ENABLE_SENTRY_TRANSACTIONS']

    config.excluded_exceptions += ['Rack::Timeout::RequestTimeoutException', 'MutexApplicationJob::LockAcquisitionError']

    # 🔒 CEVICO (auditoria 10/2026, achado #217): dados pessoais (parâmetros
    # dos pedidos = nome, telefone, conteúdo das conversas, IP) NÃO vão para o
    # Sentry por padrão. Só com ENABLE_SENTRY_PII=1 de propósito — e
    # DISABLE_SENTRY_PII continua desligando de qualquer jeito.
    config.send_default_pii = ENV['ENABLE_SENTRY_PII'].present? && ENV['DISABLE_SENTRY_PII'].blank?

    # 🔒 #217: a MENSAGEM do erro (Meta, validação) pode trazer telefone ou
    # e-mail do paciente, e o Sidekiq anexa os argumentos do job — sem PII
    # ligada, apaga os dois antes de sair
    unless config.send_default_pii
      config.before_send = lambda do |event, _hint|
        Array(event.exception&.values).each do |ex|
          next if ex.value.blank?

          ex.value = ex.value.to_s.gsub(/[\w.+-]+@[\w-]+\.[\w.]+/, '[e-mail]').gsub(/\+?\d[\d\s().-]{8,}\d/, '[número]')
        end
        sidekiq = event.contexts && (event.contexts[:sidekiq] || event.contexts['sidekiq'])
        sidekiq['args'] = '[filtrado]' if sidekiq.is_a?(Hash) && sidekiq.key?('args')
        event
      end
    end
  end
end
