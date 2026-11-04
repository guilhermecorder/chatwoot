# 🎯 item 371 (27/10): conversão do CRM DIRETO no Google Ads, pelo código
# do clique — o caminho que o gestor de tráfego pediu ("a conversão da Meta
# está melhor que a do Google").
#
# Antes: coluna do CRM → GA4 (Measurement Protocol) → o Google Ads importava
# o evento-chave, e só contava quando a identidade do navegador (cookie _ga)
# batia. Agora: coluna do CRM → Google Ads (uploadClickConversions) com
#   • gclid/gbraid/wbraid guardados no Protocolo da página (page_ads) —
#     o Google credita a conversão ao clique EXATO do anúncio;
#   • sem código de clique: conversão APRIMORADA de lead (telefone e e-mail
#     embaralhados em SHA-256), que o Google casa com quem clicou;
#   • valor + moeda (consulta: valor da consulta; cirurgia: valor real);
#   • variáveis `procedimento` (lasik, prk, catarata_trifocal…) e `pagina`.
#
# Uso:
#   Crm::GoogleAdsClickConversionService.new(account:, event_name: 'agendou_consulta', contact:,
#                                            value: 350.0, procedure: 'refrativa').call
class Crm::GoogleAdsClickConversionService
  CLICK_IDS = %w[gclid gbraid wbraid].freeze
  TZ = 'America/Sao_Paulo'.freeze

  def self.enabled?(account)
    cfg = CrmSetting.find_by(account: account)&.google_ads_config || {}
    cfg['conversions_via'].to_s == 'ads_api' && Cevico::GoogleAdsApi.new(cfg).configured?
  end

  def initialize(account:, event_name:, contact:, value: nil, currency: 'BRL', procedure: nil, page: nil, # rubocop:disable Metrics/ParameterLists
                 order_id: nil, occurred_at: nil, validate_only: false)
    @account = account
    @event_name = event_name.to_s
    @contact = contact
    @value = value
    @currency = currency.presence || 'BRL'
    @procedure = procedure
    @page = page
    @order_id = order_id
    @occurred_at = occurred_at || Time.current
    @validate_only = validate_only
  end

  def call
    @config = crm_settings&.google_ads_config || {}
    api = Cevico::GoogleAdsApi.new(@config)
    return { success: false, error: 'Google Ads (API) não configurado' } unless api.configured?

    blocked = blocker
    return { success: false, error: blocked } if blocked

    result = api.upload_click_conversions([conversion(conversion_action)], validate_only: @validate_only)
    finish(result)
  rescue StandardError => e
    { success: false, error: e.message }
  end

  # o que impede o envio (texto para a tela) ou nil
  def blocker
    return "Ação de conversão para \"#{@event_name}\" não preparada — Integrações → Google → Preparar no Google Ads" if conversion_action.blank?
    return 'Paciente sem código de clique, sem telefone e sem e-mail — nada para o Google casar' if click_id.nil? && identifiers.empty?

    nil
  end

  # a conversão como vai para o Google (camelCase = formato da API)
  def conversion(action)
    c = { conversionAction: action, conversionDateTime: @occurred_at.in_time_zone(TZ).strftime('%Y-%m-%d %H:%M:%S%:z') }
    c[click_id[:key]] = click_id[:value] if click_id
    c[:userIdentifiers] = identifiers if click_id.nil?
    c[:orderId] = @order_id.to_s[0, 64] if @order_id.present?
    c[:customVariables] = custom_variables if custom_variables.any?
    c.merge(value_fields)
  end

  def value_fields
    return {} unless @value.to_f.positive?

    { conversionValue: @value.to_f.round(2), currencyCode: @currency }
  end

  def tied?
    click_id.present?
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: @account)
  end

  def conversion_action
    @config.dig('ads_conversion_actions', @event_name).presence
  end

  # gclid (o comum), gbraid/wbraid (iPhone) — do Protocolo do contato; a
  # conversa carimbada vale como reserva
  def click_id
    return @click_id if defined?(@click_id)

    @click_id = nil
    [@contact&.additional_attributes&.dig('page_ads'), conversation_page_ads].compact.each do |ads|
      key = CLICK_IDS.find { |k| ads[k].present? }
      next unless key

      @click_id = { key: key.to_sym, value: ads[key].to_s[0, 500] }
      break
    end
    @click_id
  end

  def conversation_page_ads
    return nil if @contact.nil?

    @contact.conversations.where("jsonb_exists(conversations.additional_attributes, 'page_ads')")
            .reorder(:created_at).pick(:additional_attributes)&.dig('page_ads')
  rescue StandardError
    nil
  end

  # conversão aprimorada de lead: telefone (E.164) e e-mail em SHA-256
  def identifiers
    @identifiers ||= begin
      list = []
      phone = e164(@contact&.phone_number)
      list << { hashedPhoneNumber: sha256(phone) } if phone
      email = @contact&.email.to_s.strip.downcase
      list << { hashedEmail: sha256(email) } if email.present?
      list
    end
  end

  def e164(raw)
    digits = raw.to_s.gsub(/\D/, '')
    return nil if digits.length < 10

    digits = "55#{digits}" if digits.length <= 11 # número brasileiro sem o país
    "+#{digits}"
  end

  def sha256(text)
    Digest::SHA256.hexdigest(text.to_s)
  end

  def custom_variables
    @custom_variables ||= { 'procedimento' => @procedure, 'pagina' => @page }.filter_map do |tag, value|
      resource = @config.dig('ads_custom_variables', tag)
      next if value.blank? || resource.blank?

      { conversionCustomVariable: resource, value: value.to_s[0, 100] }
    end
  end

  def finish(result)
    base = { event_name: @event_name, tied: tied?, mode: tied? ? click_id[:key].to_s : 'aprimorada', validate_only: @validate_only }
    unless result[:ok]
      error = Array(result[:errors]).join('; ').presence || 'O Google Ads não aceitou a conversão'
      remember_error(error)
      return base.merge(success: false, error: error)
    end

    log_sent! unless @validate_only
    base.merge(success: true, job_id: result[:job_id])
  end

  # o mesmo sent_log/tied_log do envio por GA4: o painel Google soma os dois
  def log_sent!
    settings = crm_settings
    return if settings.blank?

    Cevico::SettingMerge.merge!(settings, :google_ads_config) do |cfg|
      bump(cfg, 'sent_log')
      bump(cfg, 'ads_sent_log')
      bump(cfg, 'tied_log') if tied?
      cfg['ads_last_error'] = nil
      cfg
    end
  rescue StandardError => e
    Rails.logger.warn "[GoogleAdsClickConversion] log falhou: #{e.message}"
  end

  def bump(cfg, key)
    log = (cfg[key] ||= {})
    day = (log[Date.current.iso8601] ||= {})
    day[@event_name] = day[@event_name].to_i + 1
    cfg[key] = log.sort.last(90).to_h
  end

  def remember_error(error)
    settings = crm_settings
    return if settings.blank? || @validate_only

    Cevico::SettingMerge.merge!(settings, :google_ads_config) do |cfg|
      cfg.merge('ads_last_error' => { 'at' => Time.current.iso8601, 'event' => @event_name, 'message' => error.to_s[0, 300] })
    end
  rescue StandardError => e
    Rails.logger.warn "[GoogleAdsClickConversion] erro não guardado: #{e.message}"
  end
end
