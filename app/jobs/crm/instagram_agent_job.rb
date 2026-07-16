# Orquestra o ATENDENTE INSTAGRAM em uma conversa:
# - disparado pelo CrmListener com espera de ~12s (anti-mensagem-picada:
#   se o paciente mandou outra mensagem nesse meio tempo, este job desiste
#   e o job da mensagem mais nova responde tudo de uma vez)
# - travas: kill switch, caixa permitida, conversa pausada, teto diário
# - envia as mensagens da IA (marcadas como do agente), agenda na Agenda
#   interna quando a IA confirmou dados + horário LIVRE, e pausa a conversa
#   quando a função termina (confirmação 😊) ou quando pede humano
class Crm::InstagramAgentJob < ApplicationJob
  queue_as :default

  LOG_CAP = 100

  def perform(conversation_id, trigger_message_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank? || !conversation.open?

    account = conversation.account
    state = agent_state(conversation)
    return if state['paused'] # humano assumiu / função encerrada

    # anti-picada: só responde se esta ainda é a ÚLTIMA mensagem do paciente
    last_incoming_id = conversation.messages.where(message_type: :incoming, private: false).maximum(:id)
    return if last_incoming_id != trigger_message_id

    # teto diário de segurança por conversa
    sent_today = conversation.messages
                             .where(message_type: :outgoing)
                             .where('created_at > ?', Time.current.beginning_of_day)
                             .where("additional_attributes ->> 'cevico_ia_agent' = 'instagram'")
                             .count
    if sent_today >= Crm::InstagramAgentService::MAX_REPLIES_PER_DAY
      log_event(account, conversation, 'teto_diario', 'limite de mensagens/dia atingido — pausado')
      pause!(conversation, 'teto_diario')
      return
    end

    result = Crm::InstagramAgentService.new(conversation: conversation).call
    if result[:error]
      log_event(account, conversation, 'erro', result[:error].to_s.truncate(120))
      return
    end

    # ainda é a última? (a IA demorou e o paciente mandou mais coisa)
    return if conversation.messages.where(message_type: :incoming, private: false).maximum(:id) != trigger_message_id

    send_replies(conversation, Array(result[:mensagens]))

    handle_scheduling(account, conversation, result) if result[:agendar]
    handle_human_handoff(conversation) if result[:chamar_humano]

    if result[:pausar] || result[:agendar]
      pause!(conversation, result[:agendar] ? 'agendou' : 'encerrou')
    end

    log_event(account, conversation, result[:agendar] ? 'agendou' : 'respondeu',
              "etapa #{result[:etapa]} · #{Array(result[:mensagens]).size} msg(s)")
  end

  private

  def agent_state(conversation)
    conversation.additional_attributes&.[]('cevico_atendente_ia') || {}
  end

  def pause!(conversation, reason)
    attrs = conversation.additional_attributes || {}
    attrs['cevico_atendente_ia'] = { 'paused' => true, 'reason' => reason, 'at' => Time.current.iso8601 }
    conversation.update_column(:additional_attributes, attrs) # rubocop:disable Rails/SkipsModelValidations
  end

  def send_replies(conversation, texts)
    texts.first(3).each_with_index do |text, index|
      next if text.blank?

      sleep 1.5 if index.positive? # respiro entre mensagens (humanização)
      conversation.messages.create!(
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        message_type: :outgoing,
        content: text,
        additional_attributes: { 'cevico_ia_agent' => 'instagram' }
      )
    end
  end

  def handle_scheduling(account, conversation, result)
    ag = (result[:agendamento] || {}).symbolize_keys
    date = begin
      Date.parse(ag[:dia].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    time = ag[:hora].to_s.strip

    if date.nil? || time.blank? || !Crm::AgendaSlots.slot_available?(account, date: date, time: time, unit: ag[:unidade])
      # horário inválido/ocupado (a IA não deveria, mas o sistema confere):
      # tarefa de revisão em vez de agendar errado
      account.tasks.create!(
        title: "⚠️ Confirmar consulta (Instagram): #{ag[:nome].presence || 'Paciente'}",
        description: "O Atendente Instagram confirmou um horário que o sistema não validou.\n" \
                     "Dados: #{ag.map { |k, v| "#{k}: #{v}" }.join(' · ')}\nConversa ##{conversation.display_id}",
        phone: ag[:telefone], contact: conversation.contact,
        task_type: 'consulta', priority: :high, status: :todo,
        creator: account.administrators.first || account.users.first
      )
      log_event(account, conversation, 'horario_invalido', "#{ag[:dia]} #{ag[:hora]} não validou — tarefa criada")
      return
    end

    starts_at = Crm::AgendaSlots::TZ.parse("#{date} #{time}")
    doctor = Crm::AgendaSlots.windows(account)
                             .find { |w| w['dow'] == date.wday && w['unit'] == ag[:unidade] }
                             &.[]('doctor')

    Crm::AppointmentRecorder.record(
      account: account,
      result: { found: true, starts_at: starts_at, name: ag[:nome], phone: ag[:telefone],
                unit: ag[:unidade], procedure: ag[:procedimento], doctor: doctor,
                price: 'R$ 150', notes: 'Agendado pelo Atendente Instagram (direct)' },
      contact: conversation.contact,
      conversation: conversation
    )

    update_contact_phone(conversation.contact, ag[:telefone])

    conversation.messages.create!(
      account_id: account.id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
      content: "📅 Atendente Instagram agendou: #{ag[:nome]} — #{starts_at.strftime('%d/%m/%Y às %H:%M')} " \
               "(#{ag[:unidade] == 'tatuape' ? 'Tatuapé' : 'Av. Paulista'}). Confirmação oficial segue pelo WhatsApp. " \
               "[📆 Ver na agenda](/app/accounts/#{account.id}/agenda?date=#{starts_at.strftime('%Y-%m-%d')})"
    )
  end

  # telefone captado no direct → contato ganha o número (ponte para o
  # WhatsApp assumir as confirmações oficiais)
  def update_contact_phone(contact, phone)
    return if contact.blank? || phone.blank? || contact.phone_number.present?

    digits = phone.to_s.gsub(/\D/, '')
    return if digits.length < 10

    e164 = digits.start_with?('55') ? "+#{digits}" : "+55#{digits}"
    contact.update(phone_number: e164)
  rescue StandardError => e
    Rails.logger.warn "[Crm::InstagramAgent] telefone: #{e.message}"
  end

  def handle_human_handoff(conversation)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :activity, private: true,
      content: '🙋 Atendente Instagram pediu ATENDIMENTO HUMANO nesta conversa (urgência/caso complexo). ' \
               'Responda por aqui — o agente ficará pausado; mande 👍 para reativá-lo.'
    )
    pause!(conversation, 'chamou_humano')
  end

  # registro de atividade do agente (visível no card, como os demais)
  def log_event(account, conversation, type, note)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    cfg = settings.ai_config || {}
    state = cfg['instagram_state'] || {}
    events = Array(state['events'])
    events.unshift({ 'at' => Time.current.iso8601, 'type' => type,
                     'conversation_id' => conversation.display_id,
                     'contact' => conversation.contact&.name.to_s.truncate(40), 'note' => note }.compact)
    state['events'] = events.first(LOG_CAP)
    cfg['instagram_state'] = state
    settings.update!(ai_config: cfg)
  rescue StandardError => e
    Rails.logger.warn "[Crm::InstagramAgent] log: #{e.message}"
  end
end
