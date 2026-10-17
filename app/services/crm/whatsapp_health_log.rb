# 📈 Linha do tempo da nota de cada número (Saúde do WhatsApp, 16/10/2026).
#
# A Meta só diz a nota de AGORA (verde/amarelo/vermelho) e o limite de envios;
# o Chatwoot guarda só a última leitura. Aqui fica um registro curto, por
# caixa, gravado SÓ quando algo muda (nota, limite ou situação do número) —
# poucas linhas por mês, em agenda_config['wa_health_log'].
#
# Também lê os MODELOS da Meta com a nota de qualidade de cada um (o sync do
# Chatwoot não pede quality_score) — leitura ao vivo com cache de 30 min.
module Crm::WhatsappHealthLog
  module_function

  SETTINGS_KEY = 'wa_health_log'.freeze
  PER_INBOX_CAP = 60
  HEALTH_CACHE = 10.minutes
  TEMPLATES_CACHE = 30.minutes

  def whatsapp_inboxes(account)
    account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).order(:id)
  end

  # nota ao vivo (mesmo cache do painel Início: a Meta é consultada no máximo a cada 10 min)
  def health(channel)
    Rails.cache.fetch("cevico/wa_health/#{channel.id}", expires_in: HEALTH_CACHE) do
      Whatsapp::HealthService.new(channel).fetch_health_status || {}
    rescue StandardError
      {}
    end.presence || (channel.try(:phone_number_health) || {}).symbolize_keys.presence || {}
  end

  def history(account)
    ((CrmSetting.find_by(account_id: account.id)&.agenda_config || {})[SETTINGS_KEY] || {}).to_h
  end

  # anota a leitura de agora em cada caixa (só quando mudou)
  def record!(account, now: Time.current)
    readings = whatsapp_inboxes(account).filter_map do |inbox|
      next unless inbox.channel.try(:provider) == 'whatsapp_cloud'

      h = health(inbox.channel)
      next if h[:quality_rating].blank? && h[:messaging_limit_tier].blank?

      [inbox.id.to_s, { 'q' => h[:quality_rating].to_s.upcase.presence, 'tier' => h[:messaging_limit_tier].presence,
                        'st' => h[:status].presence }.compact]
    end
    return history(account) if readings.empty?

    Cevico::SettingMerge.merge!(account, :agenda_config) do |cfg|
      log = (cfg[SETTINGS_KEY] || {}).to_h
      readings.each do |inbox_id, reading|
        entries = Array(log[inbox_id])
        last = entries.last || {}
        next if last.slice('q', 'tier', 'st') == reading

        log[inbox_id] = (entries + [reading.merge('em' => now.iso8601)]).last(PER_INBOX_CAP)
      end
      cfg[SETTINGS_KEY] = log
      cfg
    end
    history(account)
  end

  # modelos da caixa com situação e nota de qualidade (ao vivo, cache 30 min)
  def templates(channel)
    return [] unless channel.try(:provider) == 'whatsapp_cloud'

    Rails.cache.fetch("cevico/wa_templates_health/#{channel.id}", expires_in: TEMPLATES_CACHE) do
      fetch_templates(channel)
    rescue StandardError => e
      Rails.logger.warn("[CEVICO saúde whatsapp] modelos da caixa #{channel.id}: #{e.message}")
      nil
    end || fallback_templates(channel)
  end

  def fetch_templates(channel)
    waba = channel.provider_config['business_account_id']
    token = channel.try(:template_access_token).presence || channel.provider_config['api_key']
    return nil if waba.blank? || token.blank?

    version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
    url = "https://graph.facebook.com/#{version}/#{waba}/message_templates"
    list = []
    after = nil
    5.times do
      query = { fields: 'name,language,status,category,quality_score', limit: 200 }
      query[:after] = after if after
      response = HTTParty.get(url, query: query, headers: { 'Authorization' => "Bearer #{token}" }, timeout: 8)
      return nil unless response.success?

      list += Array(response['data'])
      after = response.dig('paging', 'cursors', 'after')
      break if after.blank? || response.dig('paging', 'next').blank?
    end
    list.map { |t| template_row(t) }
  end

  # sem acesso à Meta: o que o Chatwoot já tem guardado (sem a nota)
  def fallback_templates(channel)
    Array(channel.try(:message_templates)).map { |t| template_row(t) }
  end

  def template_row(tpl)
    tpl = tpl.to_h.with_indifferent_access
    quality = tpl.dig(:quality_score, :score).to_s.upcase.presence
    { name: tpl[:name], language: tpl[:language], status: tpl[:status].to_s.upcase.presence,
      category: tpl[:category].to_s.upcase.presence, quality: quality,
      quality_at: tpl.dig(:quality_score, :date) }
  end
end
