class CrmListener < BaseListener # rubocop:disable Metrics/ClassLength
  # Toda nova conversa garante um card no funil de entrada do CRM.
  # O card nasce na primeira coluna (menor position) do primeiro pipeline;
  # se o contato já tem card nesse pipeline, nada acontece.
  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    contact = conversation.contact
    return if contact.blank?

    pipeline = account.crm_pipelines.order(:position).first
    return if pipeline.blank?

    entry_stage = entry_stage_for(account, pipeline, contact)
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
    handle_responder_agents(message) # 🗣️ respondedores do WhatsApp por coluna (rodada 188)

    contact = message.conversation&.contact
    return if contact.blank?

    handle_opt_out(message, contact)

    # releitura do Secretário da Agenda (rodada 148): resposta de quem tem
    # tarefa de revisão aberta, ou pedido de remarcar/cancelar de quem tem
    # consulta futura — roda MESMO sem card no funil
    handle_scheduler_recheck(message, contact)

    # 📅 item 200: "Consulta confirmada: …" / "remarquei: …" / "consulta
    # cancelada" enviados pelo robô do N8N ou pela equipe → o Secretário lê a
    # conversa e registra na Agenda (etiqueta + card vêm de brinde)
    handle_booking_anchor(message, contact)

    # ✅ confirmação do lembrete D-1 (item 156): "sim/confirmo" de quem
    # recebeu o lembrete da véspera → marca a consulta como confirmada
    handle_appointment_confirmation(message, contact)

    # 🗺️ resposta a uma mensagem da jornada (item 168): "confirmo" / "não vou"
    Crm::Journey::ReplyService.handle(message, contact)

    # 2 consultas leves por mensagem, indexadas — barato mesmo em produção
    stage_ids = Crm::Contact.where(contact_id: contact.id).pluck(:stage_id).compact
    return if stage_ids.empty?

    Crm::Automation.where(stage_id: stage_ids, active: true, trigger_type: 'message_created').find_each do |automation|
      next unless direction_matches?(automation, message)
      next if automated_outgoing?(automation, message)
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

  # 🛑 "PARE / SAIR / não quero mais": opt-out automático (conformidade 20/09)
  def handle_opt_out(message, contact)
    return unless message.incoming? && Crm::OptOut.opt_out_message?(message.content)

    Crm::OptOut.apply!(contact, conversation: message.conversation)
  end

  # ── ÂNCORAS DE AGENDAMENTO (item 200, 22/09) ──
  # Antes, o "Deu certo 😊" do robô era o único sinal de que a consulta tinha
  # sido marcada — e a carinha PAUSAVA o robô. Agora o robô roda solto e o
  # sinal é o TEXTO da confirmação: qualquer mensagem ENVIADA (robô do N8N ou
  # equipe) com "Consulta confirmada", "remarquei", "consulta cancelada"…
  # dispara o Secretário da Agenda em 15 s. Ele lê a conversa, grava/remarca/
  # cancela na Agenda e o Crm::BookingSideEffects etiqueta o paciente e move o
  # card. Mensagens do Atendente interno (que grava sozinho, na ordem segura),
  # da jornada e dos robôs de follow-up ficam de fora. Freio: 1 leitura por
  # paciente a cada 90 s (a confirmação chega picada em 2–3 balões).
  BOOKING_ANCHORS = Regexp.union(
    /consulta\s+(confirmada|agendada|marcada|remarcada|reagendada|cancelada|desmarcada)/i,
    /\b(remarquei|reagendei|cancelei|desmarquei)\b/i
  ).freeze
  ANCHOR_THROTTLE = 90.seconds

  def handle_booking_anchor(message, contact)
    return unless booking_anchor?(message)
    return if automated_message?(message) || anchor_recently?(contact)

    Cevico::AttributeMerge.merge!(contact) do |attrs|
      attrs.merge('cevico_anchor_read_at' => Time.current.iso8601)
    end
    Crm::SchedulerRecheckJob.set(wait: 15.seconds).perform_later(message.conversation_id)
  rescue StandardError => e
    Rails.logger.error "[CrmListener] âncora de agendamento: #{e.message}"
  end

  def booking_anchor?(message)
    message.message_type == 'outgoing' && message.content.to_s.match?(BOOKING_ANCHORS)
  end

  # mensagem de robô/jornada/agente interno (marcas em additional_attributes)
  def automated_message?(message)
    attrs = message.additional_attributes || {}
    AUTOMATED_MARKS.any? { |mark| attrs[mark].present? }
  end

  def anchor_recently?(contact)
    last = contact.additional_attributes&.dig('cevico_anchor_read_at')
    return false if last.blank?

    Time.zone.parse(last.to_s) > ANCHOR_THROTTLE.ago
  rescue ArgumentError, TypeError
    false
  end

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

  # ✅ confirmação do lembrete D-1 (item 156): só age em quem TEM lembrete
  # enviado e consulta de hoje/amanhã ainda não confirmada — por isso um
  # "sim" solto de outra conversa não marca nada por engano
  CONFIRM_WORDS = Regexp.union(
    /\b(sim|s|confirmo|confirmado|confirmada|confirmar|estarei)\b/i,
    /\b(vou\s+sim|pode\s+confirmar|presenca\s+confirmada|ok|okay|blz|beleza|combinado|certo)\b/i
  )

  def handle_appointment_confirmation(message, contact) # rubocop:disable Metrics/CyclomaticComplexity
    return unless message.message_type == 'incoming'
    return unless confirmation_text?(message.content)

    marks = (contact.additional_attributes || {})['cevico_appt_reminders'] || {}
    return if marks.empty?

    task = pending_confirmation_task(contact, marks)
    return if task.nil?

    record_confirmation(message, contact, task)
  rescue StandardError => e
    Rails.logger.error "[CrmListener] confirmação de consulta: #{e.message}"
  end

  def confirmation_text?(raw)
    return true if raw.to_s.include?('👍')

    text = raw.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
    text.present? && text.match?(CONFIRM_WORDS)
  end

  # a consulta de hoje/amanhã que RECEBEU o lembrete D-1 e ainda não foi
  # confirmada — sem lembrete enviado, um "sim" solto não marca nada
  def pending_confirmation_task(contact, marks)
    today = ActiveSupport::TimeZone['America/Sao_Paulo'].now.beginning_of_day
    contact.account.tasks
           .where(id: marks.keys.map(&:to_i), task_type: 'consulta', canceled_at: nil)
           .where(due_at: today..(today + 2.days))
           .where(attendance: [nil, ''])
           .order(:due_at)
           .find { |t| marks[t.id.to_s]['d1'].present? && marks[t.id.to_s]['confirmed'].blank? }
  end

  def record_confirmation(message, contact, task)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      all = attrs['cevico_appt_reminders'] || {}
      (all[task.id.to_s] ||= {})['confirmed'] = Time.current.iso8601
      attrs.merge('cevico_appt_reminders' => all)
    end
    dia = task.due_at.in_time_zone(ActiveSupport::TimeZone['America/Sao_Paulo'])
    message.conversation.messages.create!(
      account_id: contact.account_id,
      inbox_id: message.conversation.inbox_id,
      message_type: :outgoing,
      private: true,
      content: "✅ Paciente CONFIRMOU a consulta de #{dia.strftime('%d/%m às %H:%M')} respondendo ao lembrete."
    )
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

  # ── RESPONDEDORES DO WHATSAPP POR COLUNA (rodada 188) ──
  # A COLUNA do card decide quem fala: cada agente respondedor tem suas
  # colunas (stage_ids) e, o de agendamento, também o "sem card". Mensagem do
  # paciente numa caixa permitida → acha o agente dono da coluna → job com 12s
  # de espera. Em SOMBRA nada pausa e nenhuma nota de pausa é escrita (o N8N
  # e a equipe continuam respondendo; a sombra só observa). AO VIVO, humano
  # respondendo pausa o agente e 👍 reativa — igual ao Atendente Instagram,
  # mas com estado próprio (cevico_atendente_wa).
  RESPONDER_KEYS = %w[atendente_agendamento atendente_pos].freeze
  RESPONDER_STATE_KEY = Crm::ResponderAgentJob::STATE_KEY

  def handle_responder_agents(message)
    conversation = message.conversation
    return if conversation.blank?

    cfg = CrmSetting.find_by(account_id: conversation.account_id)&.ai_config || {}
    agents = (cfg['agents'] || {}).slice(*RESPONDER_KEYS).select do |_key, a|
      a['enabled'] == true && Array(a['inbox_ids']).map(&:to_i).include?(conversation.inbox_id)
    end
    return if agents.empty?

    if message.message_type == 'incoming'
      # 👂🖼️ item 204: áudio/imagem do paciente vira texto na hora (equipe vê
      # embaixo do anexo; o Atendente lê como se fosse escrito) — em toda caixa
      # atendida, mesmo que a coluna não tenha dono ou o agente esteja pausado
      Crm::MediaReadingJob.perform_later(message.id) if Crm::MediaReadingService.message_has_media?(message)

      key = responder_owner_for(conversation, agents)
      return if key.blank?

      if Crm::ResponderAgentJob.live_mode?(agents[key])
        state = conversation.additional_attributes&.[](RESPONDER_STATE_KEY) || {}
        return if state['paused']
      end
      # item 200: responde entre 5 e 10 s da mensagem do paciente (config
      # reply_delay_seconds do agente; padrão 6 s; junta mensagens picadas)
      Crm::ResponderAgentJob.set(wait: responder_delay(agents[key])).perform_later(conversation.id, message.id, key)
    else # outgoing: só importa para quem está AO VIVO
      return unless agents.values.any? { |a| Crm::ResponderAgentJob.live_mode?(a) }
      return if message.additional_attributes&.[]('cevico_ia_agent').present? # do próprio agente
      return if message.additional_attributes&.[]('cevico_followup_bot_id').present? # robô de follow-up

      state = conversation.additional_attributes&.[](RESPONDER_STATE_KEY) || {}
      if message.content.to_s.strip == '👍'
        set_responder_pause(conversation, false)
        note_instagram(conversation, '▶️ Atendente IA do WhatsApp reativado nesta conversa (👍 do atendimento).')
      elsif !state['paused']
        set_responder_pause(conversation, true, reason: 'humano_assumiu')
        note_instagram(conversation, '⏸ Atendente IA do WhatsApp pausado — o atendimento humano assumiu esta conversa. Ligue de novo pelo botão do painel (ou mande 👍).')
      end
    end
  rescue StandardError => e
    Rails.logger.error "[CrmListener] respondedores: #{e.message}"
  end

  DEFAULT_REPLY_DELAY = 6

  def responder_delay(cfg)
    secs = cfg['reply_delay_seconds'].to_i
    secs = DEFAULT_REPLY_DELAY unless secs.positive?
    secs.clamp(3, 30).seconds
  end

  # agente dono da coluna atual do card (ou do "sem card")
  def responder_owner_for(conversation, agents) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    contact = conversation.contact
    return nil if contact.blank?

    stage_id = Crm::Contact.where(contact_id: contact.id).order(:updated_at).last&.stage_id
    agents.each do |key, a|
      return key if stage_id.present? && Array(a['stage_ids']).map(&:to_i).include?(stage_id)
      return key if stage_id.nil? && a['no_card'] == true
    end
    nil
  end

  def set_responder_pause(conversation, paused, reason: nil)
    value = paused ? { 'paused' => true, 'reason' => reason, 'at' => Time.current.iso8601 }.compact : {}
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge(RESPONDER_STATE_KEY => value) }
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

  # Paciente que JÁ TEM consulta futura na Agenda e ainda não tinha card (ex.:
  # a conversa nasceu do lembrete de véspera) NÃO é "Novo Contato": entra na
  # coluna "ao agendar" do Atendente de Agendamento. Feedback da Vaneide
  # (21/09): esses pacientes caíam em Novos Contatos e a automação da coluna
  # ("mensagem enviada → Envio de Orçamento") os jogava na coluna errada.
  # Sem coluna configurada (ou de outro funil), vale a primeira coluna.
  def entry_stage_for(account, pipeline, contact)
    first = pipeline.stages.order(:position).first
    return first if first.blank?
    return first unless Crm::AppointmentRecorder.future_appointment(account, contact.phone_number, nil, contact)

    booked_id = CrmSetting.find_by(account: account)&.ai_config&.dig('agents', 'atendente_agendamento', 'after_booking_stage_id').to_i
    (booked_id.positive? && pipeline.stages.find_by(id: booked_id)) || first
  rescue StandardError => e
    Rails.logger.warn "[CrmListener] coluna de entrada: #{e.message}"
    first
  end

  # Mensagem AUTOMÁTICA da clínica (lembrete de véspera, régua da jornada,
  # campanha, robô de follow-up, agente de IA) não é "atendente respondeu":
  # não dispara automação de coluna por mensagem ENVIADA — a menos que a
  # automação peça de propósito (action_config.include_automated = true).
  AUTOMATED_MARKS = %w[cevico_auto cevico_journey cevico_followup_bot_id cevico_ia_agent].freeze
  def automated_outgoing?(automation, message)
    return false unless message.message_type == 'outgoing'
    return false if automation.action_config&.dig('include_automated') == true

    attrs = message.additional_attributes || {}
    AUTOMATED_MARKS.any? { |k| attrs[k].present? }
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
