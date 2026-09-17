# Configuração das ligações (crm_settings.agenda_config['calls']) já com os
# padrões preenchidos — o webhook, o controller e a tela de Configurações
# leem daqui para nunca divergirem.
class Crm::Calls::Settings
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  DEFAULT_HOURS = { 'start' => '08:00', 'end' => '19:00' }.freeze
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

  def inbox_id
    raw['inbox_id'].presence&.to_i
  end

  def inbox
    return nil if inbox_id.blank?

    @inbox ||= account.inboxes.find_by(id: inbox_id)
  end

  def ring_user_ids
    Array(raw['ring_user_ids']).map(&:to_i).select(&:positive?).uniq
  end

  # quem recebe o popup: a lista configurada; vazia = membros da caixa;
  # caixa sem membros = todo mundo da conta (ninguém fica sem ouvir tocar)
  def resolved_ring_user_ids(target_inbox = inbox)
    ids = ring_user_ids
    ids = target_inbox.members.pluck(:id) if ids.empty? && target_inbox
    ids = account.users.pluck(:id) if ids.empty?
    ids
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

  # o que vai em settings_json.calls
  def to_h
    {
      enabled: enabled?, inbox_id: inbox_id, ring_user_ids: ring_user_ids,
      business_hours_only: business_hours_only?, hours: hours,
      permission_message: permission_message, record: record?, transcribe: transcribe?,
      meta: meta, updated_at: raw['updated_at']
    }
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: account)
  end
end
