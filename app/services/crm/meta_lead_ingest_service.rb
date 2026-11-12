# Ingere um lead dos FORMULÁRIOS INSTANTÂNEOS do Meta (Lead Ads): busca os
# dados na Graph API com o token da página, acha/cria o contato, guarda as
# respostas como Crm::FormResponse num formulário-espelho ("Meta: <nome>") e
# carimba a atribuição meta_ads (primeiro toque) — o lead entra nos mesmos
# relatórios de Anúncios Meta que os leads de CTWA/páginas.
# Opcional: abre uma conversa na caixa configurada com as respostas, para a
# equipe fazer o primeiro contato sem sair das Conversas.
#
# Idempotente: o mesmo leadgen_id nunca entra duas vezes (marcador _lead_id
# na resposta) — seguro rodar webhook + importação retroativa juntos.
class Crm::MetaLeadIngestService
  BASE_URI = 'https://graph.facebook.com'.freeze
  LEAD_FIELDS = 'created_time,field_data,ad_id,ad_name,adset_name,campaign_id,campaign_name,form_id,is_organic,platform'.freeze
  PHONE_KEYS = %w[phone phone_number telefone celular whatsapp].freeze
  EMAIL_KEYS = %w[email e-mail e_mail].freeze
  NAME_KEYS  = %w[full_name name nome nome_completo first_name].freeze

  def initialize(account:)
    @account = account
  end

  # leadgen_id vem do webhook; `prefetched` vem da importação retroativa
  # (o /leads da Meta já devolve o lead completo — não busca de novo).
  def ingest(leadgen_id, prefetched: nil)
    return :not_configured unless configured?

    lead = prefetched || fetch_lead(leadgen_id)
    return :error if lead.blank? || lead['field_data'].blank?

    # webhook e busca de 5 min podem pegar o mesmo lead juntos: só um entra
    # (senão o lead ganharia duas boas-vindas no WhatsApp)
    return :duplicate unless Redis::Alfred.set("crm:meta_lead:#{@account.id}:#{leadgen_id}", 1, nx: true, ex: 600)

    form = mirror_form(lead['form_id'])
    return :duplicate if duplicate?(form, leadgen_id)

    contact = find_or_create_contact(lead)
    stamp_attribution(contact, lead, leadgen_id)
    record_response(form, contact, lead, leadgen_id)
    place_card(contact)
    first_contact(contact, lead, leadgen_id)
    :imported
  rescue StandardError => e
    Rails.logger.error "[Crm::MetaLeadIngest] lead #{leadgen_id}: #{e.message}"
    :error
  end

  # Card de Integrações: valida token+página e lista os formulários com contagem.
  def test_connection
    return { success: false, error: 'Informe o ID da página e o token da página.' } unless configured?

    page = get_api(page_id, fields: 'name')
    return { success: false, error: extract_error(page) } unless page.success?

    forms = get_api("#{page_id}/leadgen_forms", fields: 'id,name,status,leads_count', limit: 25)
    return { success: false, error: extract_error(forms) } unless forms.success?

    {
      success: true,
      page_name: page.parsed_response['name'],
      forms: (forms.parsed_response['data'] || []).map do |f|
        { id: f['id'], name: f['name'], status: f['status'], leads_count: f['leads_count'] }
      end
    }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def configured?
    page_id.present? && page_token.present?
  end

  def page_id
    config['page_id'].to_s.strip
  end

  def page_token
    config['page_access_token']
  end

  def get_api(path, query = {})
    HTTParty.get("#{BASE_URI}/#{api_version}/#{path}", query: query.merge(access_token: page_token), timeout: 20)
  end

  def get_url(url)
    HTTParty.get(url, timeout: 20)
  end

  private

  def config
    @config ||= CrmSetting.find_by(account: @account)&.meta_ads_config || {}
  end

  def fetch_lead(leadgen_id)
    response = get_api(leadgen_id, fields: LEAD_FIELDS)
    return nil unless response.success?

    response.parsed_response
  end

  # Cada formulário do Meta vira um Crm::Form espelho (inativo — não aparece
  # para envio) para as respostas caírem nas telas de formulários existentes.
  def mirror_form(form_id)
    slug = "meta-#{form_id.presence || 'avulso'}"
    Crm::Form.find_by(slug: slug, account: @account) || Crm::Form.create!(
      account: @account,
      slug: slug,
      name: "Meta: #{form_name(form_id)}",
      active: false,
      questions: []
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    Crm::Form.find_by!(slug: slug, account: @account)
  end

  def form_name(form_id)
    return 'Formulário do anúncio' if form_id.blank?

    Rails.cache.fetch("crm:meta_lead_form_name:#{form_id}", expires_in: 7.days, skip_nil: true) do
      response = get_api(form_id, fields: 'name')
      response.success? ? response.parsed_response['name'] : nil
    end || 'Formulário do anúncio'
  end

  def duplicate?(form, leadgen_id)
    form.responses.where('answers @> ?', [{ 'id' => '_lead_id', 'value' => leadgen_id.to_s }].to_json).exists?
  end

  def fields_of(lead)
    Array(lead['field_data']).map { |f| f.to_h.with_indifferent_access }
  end

  def field_value(lead, keys)
    field = fields_of(lead).find { |f| keys.any? { |k| f['name'].to_s.downcase.include?(k) } }
    Array(field&.[]('values')).first.presence
  end

  # 08/11 (LIFE): número brasileiro digitado sem o 55 ("19 99999-9999") ganha
  # o código do país — senão "+19…" vira número dos EUA e a mensagem não chega
  def extract_phone(lead)
    digits = field_value(lead, PHONE_KEYS).to_s.gsub(/\D/, '').sub(/\A0+/, '')
    return nil if digits.length < 8

    digits = "55#{digits}" if digits.length.between?(10, 11)
    "+#{digits}"
  end

  def find_or_create_contact(lead)
    phone = extract_phone(lead)
    email = field_value(lead, EMAIL_KEYS)&.downcase
    name  = field_value(lead, NAME_KEYS).presence || 'Lead do Meta'

    contact   = Task.match_contact(@account, phone) if phone.present?
    contact ||= @account.contacts.find_by(email: email) if email.present?
    contact || create_contact(name, phone, email)
  end

  def create_contact(name, phone, email)
    @account.contacts.create!(name: name, phone_number: phone, email: email)
  rescue ActiveRecord::RecordInvalid
    # telefone/e-mail fora do padrão (ou corrida com outro criador): não perde
    # o lead — as respostas guardam os dados originais de qualquer forma
    (@account.contacts.find_by(email: email) if email.present?) ||
      @account.contacts.create!(name: name)
  end

  # Primeiro toque, igual ao CTWA: quem já tem meta_ads não é sobrescrito.
  # meta_lead guarda sempre o último formulário respondido.
  def stamp_attribution(contact, lead, leadgen_id)
    captured_at = lead['created_time'].presence || Time.current.iso8601
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      attrs['meta_lead'] = {
        'id' => leadgen_id.to_s,
        'form_id' => lead['form_id'],
        'created_time' => captured_at
      }.compact
      if attrs['meta_ads'].blank? && lead['ad_id'].present?
        attrs['meta_ads'] = {
          'source_id' => lead['ad_id'],
          'source_type' => 'lead_ad',
          'headline' => lead['ad_name'],
          'body' => [lead['campaign_name'], lead['adset_name']].compact_blank.join(' · ').presence,
          'captured_at' => captured_at
        }.compact
      end
      attrs
    end
  end

  def record_response(form, contact, lead, leadgen_id)
    marker = { 'id' => '_lead_id', 'label' => 'Lead (Meta)', 'type' => 'text', 'value' => leadgen_id.to_s }
    answers = [marker] + fields_of(lead).map do |f|
      { 'id' => f['name'].to_s, 'label' => f['name'].to_s.tr('_', ' ').capitalize,
        'type' => 'text', 'value' => Array(f['values']).join(', ') }
    end
    form.responses.create!(
      account: @account,
      contact: contact,
      answers: answers,
      completed_at: parse_time(lead['created_time'])
    )
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue StandardError
    Time.current
  end

  # 🗂️ 11/11 (LIFE, pedido do Guilherme): o lead do formulário nasce com
  # cartão na coluna escolhida do funil (meta_ads_config['lead_stage_id'], ex.:
  # "Formulários") ANTES da boas-vindas — senão a conversa que a boas-vindas
  # abre criaria o cartão na 1ª coluna, misturado com quem chamou no WhatsApp.
  # Quem já tem cartão nesse funil fica onde está (não volta para trás).
  def place_card(contact)
    stage_id = config['lead_stage_id'].to_i
    return unless stage_id.positive?

    stage = Crm::Stage.joins(:pipeline).find_by(id: stage_id, crm_pipelines: { account_id: @account.id })
    return if stage.nil?

    Crm::Stamp.with(via: 'robo') do
      Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: stage.pipeline_id) do |card|
        card.stage_id = stage.id
        card.origin = 'Formulário do Meta'
      end
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::MetaLeadIngest] cartão do contato #{contact&.id}: #{e.class}: #{e.message}"
  end

  # 👋 08/11 (LIFE): com a boas-vindas ligada, o lead recebe a mensagem modelo
  # no WhatsApp na hora (Crm::MetaLeadWelcome). Sem ela, vale o jeito antigo:
  # conversa na caixa configurada com as respostas, para a equipe chamar.
  def first_contact(contact, lead, leadgen_id)
    welcome = Crm::MetaLeadWelcome.new(account: @account, config: config['lead_welcome'])
    return welcome.call(contact: contact, lead: lead, leadgen_id: leadgen_id) if welcome.enabled?

    open_conversation(contact, lead, leadgen_id)
  end

  # Abre conversa na caixa configurada com as respostas formatadas — o lead
  # aparece nas Conversas na hora, pronto para o primeiro contato.
  def open_conversation(contact, lead, leadgen_id)
    inbox = @account.inboxes.find_by(id: config['lead_inbox_id'])
    return if inbox.blank?

    contact_inbox = build_contact_inbox(contact, inbox)
    return if contact_inbox.blank?

    conversation = ::Conversation.create!(
      account: @account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
      additional_attributes: { 'meta_lead_id' => leadgen_id.to_s }
    )
    conversation.messages.create!(
      account: @account, inbox: inbox, message_type: :incoming, sender: contact,
      content: format_message(lead)
    )
  rescue StandardError => e
    Rails.logger.error "[Crm::MetaLeadIngest] conversa do lead #{leadgen_id}: #{e.message}"
  end

  def build_contact_inbox(contact, inbox)
    ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
  rescue StandardError
    # canal sem source_id derivável (ex.: caixa de API) — um UUID resolve
    ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: SecureRandom.uuid).perform
  end

  def format_message(lead)
    lines = ["📋 Lead do formulário do Meta — #{form_name(lead['form_id'])}"]
    lines << "Anúncio: #{lead['ad_name']}" if lead['ad_name'].present?
    lines << ''
    fields_of(lead).each do |f|
      lines << "#{f['name'].to_s.tr('_', ' ').capitalize}: #{Array(f['values']).join(', ')}"
    end
    lines.join("\n")
  end

  def extract_error(response)
    response.parsed_response.dig('error', 'message') || "HTTP #{response.code}"
  rescue StandardError
    "HTTP #{response.code}"
  end

  def api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end
end
