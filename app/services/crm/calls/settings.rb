# Configuração das ligações (crm_settings.agenda_config['calls']) já com os
# padrões preenchidos — o webhook, o controller e a tela de Configurações
# leem daqui para nunca divergirem.
class Crm::Calls::Settings
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  DEFAULT_HOURS = { 'start' => '08:00', 'end' => '19:00' }.freeze
  # quem toca primeiro: os demais só ouvem depois desta espera (rodada 2)
  DEFAULT_CASCADE_SECONDS = 12
  CASCADE_RANGE = (5..60)
  DEFAULT_PERMISSION_MESSAGE = 'Olá! Podemos te ligar pelo WhatsApp para falar sobre o seu atendimento? ' \
                               'É só tocar em Permitir que a gente liga em seguida.'.freeze

  attr_reader :account

  def initialize(account, crm_settings: nil)
    @account = account
    @crm_settings = crm_settings
  end

  # CEVICO_CALLS_SIMULATE=1 → nada sai para a Meta (ambiente local)
  def self.simulate_env?
    ENV['CEVICO_CALLS_SIMULATE'] == '1'
  end

  def raw
    @raw ||= (crm_settings&.agenda_config || {})['calls'] || {}
  end

  def enabled?
    raw['enabled'] == true
  end

  # ── VÁRIAS CAIXAS (pedido 18/09): cada caixa tem seus atendentes, sua
  # linha de frente e sua espera. Config nova = `inboxes: [{inbox_id,
  # ring_user_ids, ring_first_user_ids, ring_cascade_seconds, meta}]`; a
  # config antiga (inbox_id + ring_user_ids soltos) vira 1 entrada sozinha.
  def inboxes
    @inboxes ||= begin
      list = Array(raw['inboxes']).map { |c| normalize_inbox(c) }.select { |c| c['inbox_id'].positive? }
      list = [normalize_inbox(raw.merge('inbox_id' => raw['inbox_id']))] if list.empty? && raw['inbox_id'].present?
      list.uniq { |c| c['inbox_id'] }
    end
  end

  def inbox_ids
    inboxes.pluck('inbox_id')
  end

  def inbox?(target_inbox)
    target_inbox.present? && inbox_ids.include?(target_inbox.id)
  end

  def inbox_config(target)
    id = target.respond_to?(:id) ? target.id : target.to_i
    inboxes.find { |c| c['inbox_id'] == id } || {}
  end

  # primeira caixa configurada (compatibilidade: rake, telas antigas)
  def inbox_id
    inbox_ids.first
  end

  def inbox
    return nil if inbox_id.blank?

    @inbox ||= account.inboxes.find_by(id: inbox_id)
  end

  def inbox_records
    account.inboxes.where(id: inbox_ids).to_a.sort_by { |i| inbox_ids.index(i.id) }
  end

  def ring_user_ids(target_inbox = inbox)
    inbox_config(target_inbox)['ring_user_ids'] || []
  end

  # quem recebe o popup: a lista da caixa; vazia = membros da caixa;
  # caixa sem membros = todo mundo da conta (ninguém fica sem ouvir tocar)
  def resolved_ring_user_ids(target_inbox = inbox)
    ids = ring_user_ids(target_inbox)
    ids = target_inbox.members.pluck(:id) if ids.empty? && target_inbox
    ids = account.users.pluck(:id) if ids.empty?
    ids
  end

  # "linha de frente": toca primeiro para estas pessoas; se ninguém atender
  # em ring_cascade_seconds, toca para o resto de quem atende
  def ring_first_user_ids(target_inbox = inbox)
    inbox_config(target_inbox)['ring_first_user_ids'] || []
  end

  def ring_cascade_seconds(target_inbox = inbox)
    inbox_config(target_inbox)['ring_cascade_seconds'] || DEFAULT_CASCADE_SECONDS
  end

  # só vale quem também está na lista de quem atende
  def resolved_ring_first_user_ids(target_inbox = inbox)
    ring_first_user_ids(target_inbox) & resolved_ring_user_ids(target_inbox)
  end

  # caixa por onde LIGAR para o paciente: a pedida (se for uma das
  # configuradas), senão a caixa da última conversa dele entre as
  # configuradas, senão a primeira configurada
  def outbound_inbox_for(contact:, preferred_id: nil)
    records = inbox_records
    return nil if records.empty?

    preferred = records.find { |i| i.id == preferred_id.to_i }
    preferred || records.find { |i| i.id == last_conversation_inbox_id(contact, records) } || records.first
  end

  def business_hours_only?
    raw['business_hours_only'] == true
  end

  def hours
    DEFAULT_HOURS.merge((raw['hours'] || {}).to_h.slice('start', 'end').compact_blank)
  end

  def within_hours?(now = TZ.now)
    hhmm = now.strftime('%H:%M')
    hhmm >= hours['start'] && hhmm < hours['end']
  end

  def permission_message
    raw['permission_message'].presence || DEFAULT_PERMISSION_MESSAGE
  end

  def record?
    raw.key?('record') ? raw['record'] == true : true
  end

  def transcribe?
    raw.key?('transcribe') ? raw['transcribe'] == true : true
  end

  # último GET/POST /settings na Meta { calling_status, callback_permission_status, checked_at, error }
  def meta
    raw['meta'] || {}
  end

  # o que vai em settings_json.calls (inbox_id/ring_* = primeira caixa, p/ compatibilidade)
  def to_h
    {
      enabled: enabled?, inboxes: inboxes, inbox_id: inbox_id, ring_user_ids: ring_user_ids,
      ring_first_user_ids: ring_first_user_ids, ring_cascade_seconds: ring_cascade_seconds,
      business_hours_only: business_hours_only?, hours: hours,
      permission_message: permission_message, record: record?, transcribe: transcribe?,
      meta: meta, updated_at: raw['updated_at']
    }
  end

  def self.normalize_inbox(config)
    c = (config || {}).to_h
    cascade = c['ring_cascade_seconds'].to_i
    {
      'inbox_id' => c['inbox_id'].to_i,
      'ring_user_ids' => id_list(c['ring_user_ids']),
      'ring_first_user_ids' => id_list(c['ring_first_user_ids']),
      'ring_cascade_seconds' => CASCADE_RANGE.cover?(cascade) ? cascade : DEFAULT_CASCADE_SECONDS,
      'meta' => (c['meta'] || {}).to_h
    }
  end

  def self.id_list(value)
    Array(value).map(&:to_i).select(&:positive?).uniq
  end

  private

  def normalize_inbox(config)
    self.class.normalize_inbox(config)
  end

  def last_conversation_inbox_id(contact, records)
    return nil if contact.nil?

    account.conversations.where(contact_id: contact.id, inbox_id: records.map(&:id)).order(created_at: :desc).pick(:inbox_id)
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: account)
  end
end
