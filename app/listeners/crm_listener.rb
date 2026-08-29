class CrmListener < BaseListener
  # Toda nova conversa garante um card no funil de entrada do CRM.
  # O card nasce na primeira coluna (menor position) do primeiro pipeline;
  # se o contato já tem card nesse pipeline, nada acontece.
  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    contact = conversation.contact
    return if contact.blank?

    pipeline = account.crm_pipelines.order(:position).first
    return if pipeline.blank?

    entry_stage = pipeline.stages.order(:position).first
    return if entry_stage.blank?

    Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: pipeline.id) do |card|
      card.stage_id = entry_stage.id
      card.origin = conversation.inbox&.name
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # corrida entre eventos simultâneos do mesmo contato — card já existe
    nil
  end

  # Gatilho "Mensagem criada" das automações de coluna: quando chega uma
  # mensagem na conversa, dispara as automações desse gatilho na coluna
  # onde o card do contato está AGORA. Config na automação (action_config):
  # - message_direction: incoming (padrão) | outgoing | both
  # - message_contains: frases-chave (vírgula = OU, "aspas" = frase exata;
  #   ignora acento/maiúsculas). Vazio = qualquer mensagem.
  # - throttle_minutes: no máximo 1 disparo a cada N min por contato
  #   (0/vazio = sem limite — ex.: acionar fluxo n8n a cada mensagem)
  def message_created(event)
    message = event.data[:message]
    return if message.blank? || message.private?
    return unless %w[incoming outgoing].include?(message.message_type)

    handle_instagram_agent(message) # Atendente IA das caixas configuradas

    contact = message.conversation&.contact
    return if contact.blank?

    # releitura do Secretário da Agenda (rodada 148): resposta de quem tem
    # tarefa de revisão aberta, ou pedido de remarcar/cancelar de quem tem
    # consulta futura — roda MESMO sem card no funil
    handle_scheduler_recheck(message, contact)

    # 2 consultas leves por mensagem, indexadas — barato mesmo em produção
    stage_ids = Crm::Contact.where(contact_id: contact.id).pluck(:stage_id).compact
    return if stage_ids.empty?

    Crm::Automation.where(stage_id: stage_ids, active: true, trigger_type: 'message_created').find_each do |automation|
      next unless direction_matches?(automation, message)
      next unless content_matches?(automation, message)
      next if throttled?(automation, contact)

      delay = automation.delay_minutes.to_i
      job = delay.positive? ? CrmAutomationFireJob.set(wait: delay.minutes) : CrmAutomationFireJob
      job.perform_later(automation.id, contact.id, {
                          event_type: 'message_created',
                          message_id: message.id,
                          message_direction: message.message_type
                        })
    end
  end

  private

  # ── RELEITURA DO SECRETÁRIO DA AGENDA (rodada 148) ──
  # O gatilho de coluna lê a conversa quando o card ENTRA — muitas vezes antes
  # de dia/hora estarem combinados. Aqui a leitura ganha segunda chance:
  # (a) paciente com tarefa "⚠️ Confirmar consulta"/"⚠️ Pediu cancelar" aberta
  #     responde → relê (qualquer mensagem dele; é a confirmação chegando);
  # (b) mensagem fala em remarcar/cancelar E o paciente tem consulta futura
  #     na Agenda → relê (reagendamento/cancelamento entram sozinhos).
  # Freios: 1 releitura por paciente a cada 10 min + espera de 20s (junta
  # mensagens picadas) + o próprio Applier corta leituras quase simultâneas.
  RECHECK_TERMS = [
    'remarcar', 'reagendar', 'desmarcar', 'cancelar', 'adiar',
    'mudar o horario', 'trocar o horario', 'outro horario', 'outro dia',
    'nao vou conseguir', 'nao vou poder', 'nao poderei'
  ].freeze
  RECHECK_THROTTLE = 10.minutes

  def handle_scheduler_recheck(message, contact)
    return unless message.message_type == 'incoming'
    return if recheck_recently?(contact)

    account = message.conversation.account
    return unless recheck_trigger?(account, contact, message)

    Cevico::AttributeMerge.merge!(contact) do |attrs|
      attrs.merge('cevico_scheduler_recheck_at' => Time.current.iso8601)
    end
    Crm::SchedulerRecheckJob.set(wait: 20.seconds).perform_later(message.conversation_id)
  rescue StandardError => e
    Rails.logger.error "[CrmListener] releitura do Secretário: #{e.message}"
  end

  def recheck_recently?(contact)
    last = contact.additional_attributes&.dig('cevico_scheduler_recheck_at')
    return false if last.blank?

    Time.zone.parse(last.to_s) > RECHECK_THROTTLE.ago
  rescue ArgumentError, TypeError
    false
  end

  def recheck_trigger?(account, contact, message)
    open_tasks = account.tasks.where(status: %i[todo doing], contact_id: contact.id)
    # (a) tarefa de revisão aberta do paciente → qualquer resposta reabre a leitura
    return true if open_tasks.where("title LIKE '⚠️ Confirmar consulta%' OR title LIKE '⚠️ Pediu cancelar%'").exists?

    # (b) palavras de remarcação/cancelamento de quem TEM consulta futura
    content = normalize_text(message.content)
    return false if content.blank?
    return false unless RECHECK_TERMS.any? { |t| content.include?(t) }

    account.tasks.where(task_type: 'consulta', canceled_at: nil, contact_id: contact.id)
           .where('due_at > ?', Time.current)
           .where.not(status: 'done')
           .exists?
  end

  # ── ATENDENTE INSTAGRAM (agente respondedor por caixa) ──
  # incoming na caixa configurada → agenda o job com 12s de espera (junta
  # mensagens picadas). Outgoing HUMANO na mesma caixa → PAUSA o agente;
  # humano mandando 👍 → REATIVA. Mensagens do próprio agente e de robôs
  # de follow-up não mexem na pausa.
  def handle_instagram_agent(message)
    conversation = message.conversation
    return if conversation.blank?

    cfg = CrmSetting.find_by(account_id: conversation.account_id)&.ai_config || {}
    agent = (cfg['agents'] || {})['instagram'] || {}
    return unless agent['enabled'] == true
    return unless Array(agent['inbox_ids']).map(&:to_i).include?(conversation.inbox_id)

    if message.message_type == 'incoming'
      state = conversation.additional_attributes&.[]('cevico_atendente_ia') || {}
      return if state['paused']

      Crm::InstagramAgentJob.set(wait: 12.seconds).perform_later(conversation.id, message.id)
    else # outgoing
      return if message.additional_attributes&.[]('cevico_ia_agent').present? # do próprio agente
      return if message.additional_attributes&.[]('cevico_followup_bot_id').present? # robô de follow-up

      if message.content.to_s.strip == '👍'
        set_instagram_pause(conversation, false)
        note_instagram(conversation, '▶️ Atendente IA reativado nesta conversa (👍 do atendimento).')
      else
        state = conversation.additional_attributes&.[]('cevico_atendente_ia') || {}
        return if state['paused'] # já estava pausado — não repete a nota

        set_instagram_pause(conversation, true, reason: 'humano_assumiu')
        note_instagram(conversation, '⏸ Atendente IA pausado — o atendimento humano assumiu esta conversa. Mande 👍 para reativar.')
      end
    end
  rescue StandardError => e
    Rails.logger.error "[CrmListener] atendente instagram: #{e.message}"
  end

  def set_instagram_pause(conversation, paused, reason: nil)
    value = paused ? { 'paused' => true, 'reason' => reason, 'at' => Time.current.iso8601 }.compact : {}
    # merge atômico: não atropela o estado do follow-up gravado em paralelo
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge('cevico_atendente_ia' => value) }
  end

  def note_instagram(conversation, content)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :activity, private: true, content: content
    )
  end

  def direction_matches?(automation, message)
    direction = automation.action_config&.dig('message_direction').presence || 'incoming'
    direction == 'both' || message.message_type == direction
  end

  # frases-chave: mesma sintaxe do Tratamento de dados (vírgula = OU,
  # "aspas" = frase exata como uma peça só), ignorando acento e caixa
  def content_matches?(automation, message)
    raw = automation.action_config&.dig('message_contains').to_s
    return true if raw.blank?

    terms = Crm::RetroLabelJob.parse_terms(raw)
    return true if terms.empty?

    content = normalize_text(message.content)
    return false if content.blank?

    terms.any? { |term| content.include?(normalize_text(term)) }
  end

  def normalize_text(text)
    ActiveSupport::Inflector.transliterate(text.to_s).downcase
  end

  def throttled?(automation, contact)
    throttle = automation.action_config&.dig('throttle_minutes').to_i
    return false unless throttle.positive?

    Crm::AutomationLog.where(automation: automation, contact_id: contact.id)
                      .where('fired_at > ?', throttle.minutes.ago)
                      .exists?
  end
end
