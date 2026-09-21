# 📞 Seleção de LEADS NÃO RESPONSIVOS para o Agente de Ligação (rodada 195).
# Quem entra na lista de hoje: contato com card numa das COLUNAS VIGIADAS
# (agents.voice.stage_ids), com telefone, cuja ÚLTIMA mensagem de conversa é
# da clínica (outgoing: humana ou robô) há pelo menos `silence_hours` e no
# máximo `lookback_days` — ou seja, a clínica falou por último e o paciente
# sumiu. Fica de fora quem: respondeu depois, já tem consulta futura, pediu
# para não ser incomodado (Crm::OptOut), recebeu ligação da IA nas últimas
# 48 h ou já teve `max_attempts` ligações em 14 dias, ou está na fila de uma
# campanha de ligação aberta. Cada candidato traz um `motivo` legível (tela)
# e um `objective` falado ({{campanha_objetivo}} da ligação).
class Crm::VoiceAgent::UnresponsiveLeads
  DEFAULTS = { 'silence_hours' => 24, 'lookback_days' => 7, 'max_attempts' => 2, 'daily_cap' => 20 }.freeze
  LIMITS = { 'silence_hours' => 1..168, 'lookback_days' => 1..60, 'max_attempts' => 1..5, 'daily_cap' => 1..200 }.freeze
  ATTEMPT_GAP = 48.hours   # duas ligações da IA nunca a menos de 48 h
  ATTEMPT_WINDOW = 14.days # max_attempts conta dentro desta janela
  OPEN_CAMPAIGN_STATUSES = %w[draft scheduled processing paused].freeze
  TZ = Crm::VoiceAgent::Settings::TZ

  # valor da config com padrão e limite (a tela e o controller usam o mesmo)
  def self.setting(cfg, key)
    value = (cfg || {})[key].to_i
    value = DEFAULTS[key] unless value.positive?
    value.clamp(LIMITS[key].min, LIMITS[key].max)
  end

  attr_reader :account, :cfg

  def initialize(account, cfg, now: TZ.now)
    @account = account
    @cfg = (cfg || {}).to_h
    @now = now
  end

  def silence_hours = self.class.setting(cfg, 'silence_hours')
  def lookback_days = self.class.setting(cfg, 'lookback_days')
  def max_attempts = self.class.setting(cfg, 'max_attempts')
  def daily_cap = self.class.setting(cfg, 'daily_cap')

  def stage_ids
    ids = Array(cfg['stage_ids']).map(&:to_i).select(&:positive?)
    return [] if ids.empty?

    Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }, id: ids).pluck(:id)
  end

  # lista do dia, os mais recentes primeiro (quem parou de responder há menos
  # tempo tem mais chance de atender), até `limit`
  def candidates(limit: daily_cap)
    ids = stage_ids
    return [] if ids.empty?

    cards = Crm::Contact.where(stage_id: ids).includes(:contact, :stage).to_a
    cards.select! { |card| dialable?(card.contact) }
    cards.reject! { |card| excluded_ids.include?(card.contact_id) }
    last = last_messages_by_contact(cards.map(&:contact_id))
    items = cards.filter_map { |card| candidate(card, last[card.contact_id]) }
    items.sort_by { |item| item['last_message_at'] }.reverse.first(limit)
  end

  private

  def dialable?(contact)
    return false if contact.blank? || contact.phone_number.to_s.gsub(/\D/, '').length < 8

    contact.phone_number != Crm::AgentSimulator::FAKE_PHONE # paciente de teste do simulador nunca entra
  end

  # opt-out (nao_perturbe / perda_*) + fila de campanha aberta
  def excluded_ids
    @excluded_ids ||= begin
      campaign_ids = Crm::CallCampaign.where(account_id: account.id, status: OPEN_CAMPAIGN_STATUSES).pluck(:id)
      queued = Crm::CallCampaignContact.where(call_campaign_id: campaign_ids, status: %w[queued calling]).pluck(:contact_id)
      (Crm::OptOut.excluded_contact_ids(account) + queued).to_set
    end
  end

  # última mensagem REAL (incoming/outgoing, não privada) de cada contato dentro
  # da janela — uma query com DISTINCT ON por conversa, depois a mais nova por
  # contato. Mensagem mais nova fora da janela não existe (a janela vai até
  # agora), então "mais nova na janela" = "mais nova de todas".
  def last_messages_by_contact(contact_ids)
    return {} if contact_ids.empty?

    conversations = account.conversations.where(contact_id: contact_ids).pluck(:id, :contact_id).to_h
    return {} if conversations.empty?

    rows = Message.where(conversation_id: conversations.keys, message_type: %i[incoming outgoing], private: false)
                  .where(created_at: (@now - lookback_days.days)..)
                  .select('DISTINCT ON (messages.conversation_id) messages.id, messages.conversation_id, messages.message_type, ' \
                          'messages.content, messages.created_at')
                  .reorder(Arel.sql('messages.conversation_id, messages.created_at DESC, messages.id DESC')) # Message tem default_scope de ordem
    rows.to_a.group_by { |m| conversations[m.conversation_id] }.transform_values { |list| list.max_by(&:created_at) }
  end

  def candidate(card, message)
    return nil if message.blank? || !message.outgoing?
    return nil if message.created_at > @now - silence_hours.hours

    contact = card.contact
    return nil if Crm::AppointmentRecorder.future_appointment(account, contact.phone_number, nil, contact).present?
    return nil unless attempts_ok?(contact.id)

    build_item(card, contact, message)
  end

  # ligações da IA: nenhuma nas últimas 48 h e menos que max_attempts em 14 dias
  def attempts_ok?(contact_id)
    calls = ai_calls[contact_id]
    return true if calls.blank?

    calls[:count] < max_attempts && calls[:last] < @now - ATTEMPT_GAP
  end

  def ai_calls
    @ai_calls ||= Crm::Call.by_ai.where(account_id: account.id).where(started_at: (@now - ATTEMPT_WINDOW)..)
                           .where.not(contact_id: nil).group(:contact_id)
                           .pluck(:contact_id, Arel.sql('COUNT(*)'), Arel.sql('MAX(started_at)'))
                           .to_h { |contact_id, count, last| [contact_id, { count: count, last: last }] }
  end

  def build_item(card, contact, message)
    hours = ((@now - message.created_at) / 1.hour).floor
    digits = contact.phone_number.to_s.gsub(/\D/, '')
    excerpt = message.content.to_s.squish.truncate(70)
    stage = card.stage&.name.to_s
    {
      'contact_id' => contact.id, 'name' => contact.name.to_s, 'phone_final' => digits.last(4),
      'stage_id' => card.stage_id, 'stage' => stage, 'conversation_id' => conversation_display_id(message),
      'last_message_at' => message.created_at.iso8601, 'hours_silent' => hours, 'excerpt' => excerpt,
      'motivo' => "#{stage} · sem resposta há #{elapsed_label(hours)} · última mensagem: “#{excerpt}”",
      'objective' => "conversa parada na etapa #{stage}: a clínica mandou a última mensagem pelo WhatsApp " \
                     "#{Crm::VoiceAgent::Script.spoken_elapsed(hours)} e a pessoa não respondeu"
    }
  end

  def conversation_display_id(message)
    Conversation.where(id: message.conversation_id).pick(:display_id)
  end

  # "30 h" / "3 dias"
  def elapsed_label(hours)
    hours < 48 ? "#{hours} h" : "#{hours / 24} dias"
  end
end
