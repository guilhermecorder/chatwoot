# 📣 item 345 (14/10): botão "Testar envio" da Meta. Antes mandava um PageView
# sem contato → user_data vazio → a Meta respondia só "Invalid parameter".
# Agora testa OS DOIS caminhos, um por destino:
#   · Site (pixel_id) — evento comum, como o lead da página;
#   · cada caixa do WhatsApp da CEVICO — evento de MENSAGEM no conjunto da
#     conta do WhatsApp (acha ou cria o conjunto; parceiros ficam de fora).
# Sempre com código de teste (o configurado ou TEST_CEVICO): cai na aba
# "Testar eventos" da Meta e NUNCA conta nas campanhas — por isso aqui vale
# até em produção. Site: telefone de mentira (embaralhado). WhatsApp: o CLIQUE
# REAL do lead de anúncio mais recente daquela caixa (últimos 7 dias) — com
# código de clique inventado a Meta sempre recusava ("ctwa_clid inválido",
# subcode 2804087) e o botão acusava erro falso (14/10). Caixa sem lead de
# anúncio na semana: conjunto pronto, nada a testar (⚪).
class Crm::MetaAdsTestService
  FALLBACK_TEST_CODE = 'TEST_CEVICO'.freeze
  TEST_PHONE = '5511999999999'.freeze
  CLICK_WINDOW = 7.days
  NO_LEAD_NOTE = 'conjunto pronto — nenhum lead de anúncio de WhatsApp nesta caixa nos últimos 7 dias para testar'.freeze

  def initialize(account:)
    @account = account
    @config = CrmSetting.find_by(account: account)&.meta_ads_config || {}
  end

  def call
    return { success: false, error: 'Meta Ads não configurado', results: [] } unless configured?

    results = [site_result] + datasets.channels.map { |c| whatsapp_result(c) }
    Rails.logger.info "[MetaAdsTest] conta=#{@account.id} #{results.map { |r| "#{r[:target]}=#{r[:ok] ? 'ok' : 'erro'}" }.join(' · ')}"
    failed = results.reject { |r| r[:ok] }
    { success: failed.empty?, test_event_code: test_code, results: results,
      error: failed.map { |r| "#{r[:target]}: #{r[:error]}" }.join(' · ').presence }
  end

  private

  def configured?
    @config['pixel_id'].present? && @config['access_token'].present?
  end

  def datasets
    @datasets ||= Crm::MetaWabaDatasets.new(@account, @config)
  end

  def test_code
    @config['test_event_code'].presence || FALLBACK_TEST_CODE
  end

  def site_result
    pixel = @config['pixel_id']
    result = guarded { Crm::MetaWabaDatasets.post_events(pixel, @config['access_token'], payload(site_event)) }
    row("Site (pixel #{pixel})", pixel, result.merge(token: 'sistema'))
  end

  def whatsapp_result(entry)
    target = "Caixa #{entry[:inbox].id} #{entry[:inbox].name}"
    dataset = datasets.dataset_id(entry[:waba_id], fresh: true)
    if dataset.blank?
      return row(target, nil, { ok: false, error: "Não consegui achar nem criar o conjunto desta conta do WhatsApp: #{datasets.last_error}" })
    end

    lead = ad_lead(entry[:inbox].id)
    return row(target, dataset, { ok: true, token: nil }, skipped: true, note: NO_LEAD_NOTE) unless lead

    result = guarded { datasets.post_events(entry[:waba_id], dataset, payload(messaging_event(entry[:waba_id], lead))) }
    row(target, dataset, result, note: 'testado com o clique real de um lead de anúncio (evento de teste)')
  end

  def row(target, dataset_id, result, skipped: false, note: nil)
    { target: target, dataset_id: dataset_id, ok: result[:ok] == true, error: result[:ok] ? nil : result[:error],
      token: result[:token], skipped: skipped, note: note }
  end

  # o lead de anúncio de WhatsApp mais recente desta caixa (o clique dele é real)
  def ad_lead(inbox_id)
    @account.conversations.where(inbox_id: inbox_id).where('conversations.created_at > ?', CLICK_WINDOW.ago)
            .joins(:contact).where("COALESCE(contacts.additional_attributes -> 'meta_ads' ->> 'ctwa_clid', '') <> ''")
            .reorder('conversations.created_at DESC').first&.contact
  end

  # erro de rede num destino não derruba a lista inteira (e não vaza token)
  def guarded
    yield
  rescue StandardError => e
    { ok: false, error: e.message.to_s.gsub(/access_token=[^&\s]+/, 'access_token=[token]') }
  end

  def payload(event)
    { data: [event], test_event_code: test_code }
  end

  def base_event(name, source)
    { event_name: name, event_time: Time.current.to_i, event_id: "cevico_teste_#{SecureRandom.hex(8)}",
      action_source: source, user_data: { ph: [Digest::SHA256.hexdigest(TEST_PHONE)] } }
  end

  def site_event
    base_event('Lead', 'system_generated')
  end

  def messaging_event(waba, lead)
    event = base_event('LeadSubmitted', 'business_messaging')
    event[:messaging_channel] = 'whatsapp'
    phone = lead.phone_number.to_s.gsub(/\D/, '')
    event[:user_data] = event[:user_data].merge(ctwa_clid: lead.additional_attributes.dig('meta_ads', 'ctwa_clid'),
                                                whatsapp_business_account_id: waba)
    event[:user_data][:ph] = [Digest::SHA256.hexdigest(phone)] if phone.present?
    event
  end
end
