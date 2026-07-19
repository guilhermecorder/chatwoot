# Roda a cada 2 min (schedule.yml). Para cada robô ativo, procura conversas
# em que o PACIENTE ficou em silêncio (última mensagem foi do atendimento) e
# envia as "cutucadas" da cadência conforme o tempo decorrido.
#
# Âncora = primeira mensagem outgoing depois da última mensagem do paciente.
# Assim, enviar uma cutucada (nova outgoing) NÃO reinicia o cronômetro.
# Se o paciente responder (nova incoming), a âncora deixa de existir e o
# marcador é limpo — a cadência para sozinha.
#
# Cada robô guarda seu REGISTRO DE ATIVIDADE (activity_log): resumo da última
# rodada com os motivos de cada conversa não cutucada + histórico dos envios.
# É onde se entende, em produção, por que o robô está (ou não) enviando.
class Crm::FollowupBotJob < ApplicationJob
  queue_as :scheduled_jobs

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  LOOKBACK = 3.days # não cutuca conversas antigas demais
  EVENTS_CAP = 60   # histórico de envios/erros guardado por robô
  # EXPEDIENTE: cutucada só entre 08h e 20h (SP) — nada de mensagem às 6h
  BUSINESS_HOURS = (8...20)
  # etapa que venceu há mais de N horas PERDEU O MOMENTO: é marcada como
  # tratada SEM enviar (evita rajada após deploy/queda — o robô não manda
  # 4 cutucadas atrasadas de uma vez)
  STALE_HOURS = 3
  # ── TRAVA FÍSICA (incidente 18/07: rajadas de 2 em 2 min) ──
  # A fonte da VERDADE são as mensagens já enviadas (cada cutucada carrega
  # cevico_followup_bot_id), não o marcador em additional_attributes — que
  # pode ser apagado por um escritor concorrente. Mesmo sem marcador nenhum,
  # o robô NUNCA passa destes limites por conversa:
  MIN_GAP_MINUTES = 30 # piso entre cutucadas (qualquer robô) na mesma conversa
  DAILY_CAP = 4        # teto diário de cutucadas (qualquer robô) na mesma conversa

  def perform
    # TRAVA: cron a cada 2 min. Se uma rodada demora mais que isso (muitas
    # conversas abertas), a seguinte começava por cima e podia cutucar o mesmo
    # paciente 2× antes do persist_state. O lock faz a rodada nova pular.
    lock_manager = Redis::LockManager.new
    lock_key = 'CRM_FOLLOWUP_BOT_JOB_LOCK'
    return unless lock_manager.lock(lock_key, 10.minutes)

    begin
      Crm::FollowupBot.active.includes(:inbox).find_each { |bot| process_bot(bot) }
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  private

  def process_bot(bot)
    unless bot.within_window? # janela "começa em / para em"
      record_run(bot, status: 'fora_da_janela')
      return
    end

    unless BUSINESS_HOURS.cover?(TZ.now.hour) # expediente 08h–20h SP
      record_run(bot, status: 'fora_do_expediente')
      return
    end

    steps = bot.ordered_steps
    return record_run(bot, status: 'sem_etapas') if steps.blank?

    # UMA conversa por contato: a de última atividade (caixa prioritária) —
    # evita cutucar o mesmo paciente em várias caixas de entrada ao mesmo tempo.
    ids = conversations(bot)
          .select('DISTINCT ON (conversations.contact_id) conversations.id')
          .order('conversations.contact_id, conversations.last_activity_at DESC')
          .map(&:id)

    run = { status: 'ok', candidates: ids.size, sent: 0, reasons: Hash.new(0) }
    events = []

    # eager-load do contato + inbox: evita 1 query por conversa só pra achar o
    # contato/etiquetas na hora de decidir a cutucada
    Conversation.where(id: ids).includes(:contact, :inbox).find_each do |conversation|
      process_conversation(bot, conversation, steps, run, events)
    rescue StandardError => e
      run[:reasons]['erro'] += 1
      events << event_for(conversation, 'error', note: e.message.truncate(120))
      Rails.logger.error("[CEVICO followup] conversa #{conversation.id}: #{e.message}")
    end

    record_run(bot, **run, events: events)
  end

  def conversations(bot)
    scope = bot.account.conversations
               .where(status: :open)
               .where('conversations.last_activity_at >= ?', LOOKBACK.ago)

    if bot.stage_scoped?
      # cards que estão na coluna → conversas desses contatos
      contact_ids = Crm::Contact.where(stage_id: bot.stage_id).select(:contact_id)
      scope = scope.where(contact_id: contact_ids)
      # caixa escolhida no robô de coluna → restringe a esse número
      scope = scope.where(inbox_id: bot.inbox_id) if bot.inbox_id.present?
    else
      # caixa automática: sem inbox definida, roda em todas as conversas
      # abertas — a mensagem sai pelo número da própria conversa
      scope = scope.where(inbox_id: bot.inbox_id) if bot.inbox_id.present?
    end
    scope
  end

  def process_conversation(bot, conversation, steps, run, events)
    # TRAVA individual: atendente pausou o follow-up para este paciente
    # (botão na janelinha da conversa) — nenhum robô cutuca
    return run[:reasons]['pausado_para_paciente'] += 1 if conversation.contact&.additional_attributes&.[]('cevico_followup_paused').present?

    return run[:reasons]['etiquetas'] += 1 unless labels_match?(bot, conversation.contact)

    anchor = silence_anchor(conversation)
    # paciente falou por último → quem deve responder é o atendimento, não o robô
    return run[:reasons]['paciente_falou_ultimo'] += 1 if anchor.nil?

    stage_entered = stage_entry_at(bot, conversation) # nil se não for robô de coluna
    state = followup_state(conversation, bot, anchor, stage_entered)
    silence_hours = (Time.current - anchor) / 3600.0

    # etapas VENCIDAS ainda não tratadas (com quanto tempo de atraso cada uma)
    due = []
    steps.each_with_index do |step, index|
      from_stage = step['delay_from'] == 'stage_entry'
      # etapas "desde a entrada na coluna" têm marcador PRÓPRIO, amarrado à
      # entrada na coluna — resposta do paciente não as redispara.
      sent_list = from_stage ? state['stage_sent'] : state['sent']
      next if sent_list.include?(index)

      base_hours = from_stage ? hours_since(stage_entered) : silence_hours
      delay = Crm::FollowupBot.step_delay_hours(step)
      next if base_hours.nil? || base_hours < delay

      due << { step: step, index: index, from_stage: from_stage, overdue: base_hours - delay }
    end

    if due.empty?
      if (state['sent'] + state['stage_sent']).size >= steps.size
        run[:reasons]['cadencia_completa'] += 1
      else
        run[:reasons]['aguardando_prazo'] += 1
      end
      return
    end

    # ANTI-RAJADA: manda no máximo UMA cutucada por conversa por rodada —
    # a de maior prazo entre as vencidas (as anteriores perderam a vez).
    chosen = due.max_by { |d| Crm::FollowupBot.step_delay_hours(d[:step]) }

    if chosen[:overdue] > STALE_HOURS
      # venceu há horas (deploy/queda/madrugada): marca como tratada SEM
      # enviar — cutucada velha às 6h da manhã não ajuda ninguém
      mark_steps(state, due)
      persist_state(conversation, bot, anchor, state)
      run[:reasons]['momento_perdido'] += 1
      events << event_for(conversation, 'skipped',
                          note: "#{step_label(chosen[:step])} venceu há #{chosen[:overdue].round}h — não enviada")
      return
    end

    # ── TRAVA FÍSICA: consulta as cutucadas REALMENTE enviadas (tabela de
    # mensagens) antes de qualquer envio. Protege o paciente mesmo que o
    # marcador tenha sido apagado/corrompido por outro processo.
    nudges = bot_nudges(conversation)
    sent_since_anchor = nudges.where('created_at >= ?', anchor).count
    if sent_since_anchor >= steps.size
      # cadência já saiu inteira nas mensagens → ressincroniza o marcador
      mark_steps(state, due)
      persist_state(conversation, bot, anchor, state)
      run[:reasons]['trava_cadencia_completa'] += 1
      return
    end

    last_nudge_at = nudges.maximum(:created_at)
    if last_nudge_at && last_nudge_at > MIN_GAP_MINUTES.minutes.ago
      run[:reasons]['trava_intervalo_minimo'] += 1
      return
    end

    if nudges.where('created_at >= ?', TZ.now.beginning_of_day).count >= DAILY_CAP
      run[:reasons]['trava_teto_diario'] += 1
      return
    end

    # marca ANTES de enviar (falha segura): se o envio quebrar no meio, o
    # pior caso é PERDER uma cutucada — nunca duplicar para o paciente
    mark_steps(state, due) # as vencidas anteriores são absorvidas pela enviada
    persist_state(conversation, bot, anchor, state)
    send_nudge(bot, conversation, chosen[:step])
    run[:sent] += 1
    events << event_for(conversation, 'sent', note: step_label(chosen[:step]))
  end

  # cutucadas de QUALQUER robô de follow-up nesta conversa (mensagens reais)
  def bot_nudges(conversation)
    conversation.messages.outgoing
                .where("additional_attributes ->> 'cevico_followup_bot_id' IS NOT NULL")
  end

  def mark_steps(state, due)
    due.each do |d|
      list = d[:from_stage] ? state['stage_sent'] : state['sent']
      list << d[:index] unless list.include?(d[:index])
    end
  end

  # quando o card entrou na coluna do robô (só robô de coluna)
  def stage_entry_at(bot, conversation)
    return nil unless bot.stage_scoped? && conversation.contact_id

    crm = Crm::Contact.find_by(pipeline_id: bot.stage.pipeline_id, contact_id: conversation.contact_id)
    return nil unless crm

    # fallback ESTÁVEL: stage_moved_at (quando entrou na coluna atual) e, por
    # fim, created_at. Antes caía em updated_at, que muda a QUALQUER edição do
    # card (valor, nota) → o marcador da etapa mudava e a cadência de coluna
    # RECOMEÇAVA, reenviando cutucadas ao paciente.
    Crm::StageLog.where(crm_contact_id: crm.id, stage_id: bot.stage_id).maximum(:entered_at) ||
      crm.stage_moved_at || crm.created_at
  end

  def hours_since(time)
    return nil if time.nil?

    (Time.current - time) / 3600.0
  end

  # Filtros "tem / não tem": só cutuca quem TEM todas as etiquetas exigidas
  # e NÃO TEM nenhuma das excluídas (etiquetas do contato).
  def labels_match?(bot, contact)
    return false if contact.blank?

    required = Array(bot.required_labels).map(&:to_s)
    excluded = Array(bot.exclude_labels).map(&:to_s)
    return true if required.empty? && excluded.empty?

    contact_labels = contact.label_list.map(&:to_s)
    return false if required.any? && (required - contact_labels).any?
    return false if excluded.any? && contact_labels.intersect?(excluded)

    true
  end

  # primeira outgoing depois da última incoming; nil se a última msg for do paciente.
  #
  # ⚠️ BUG HISTÓRICO (corrigido 2026-07-15): Message tem default_scope
  # ordenando por created_at ASC, que vence o .order(desc) — "última mensagem"
  # vinha a PRIMEIRA da conversa. O robô só funcionava quando a conversa
  # começava com mensagem do atendimento (caso do teste) e nunca nas conversas
  # reais (paciente fala primeiro). Comparação por maximum() não sofre disso.
  def silence_anchor(conversation)
    msgs = conversation.messages.where(message_type: [:incoming, :outgoing])
    last_incoming_at = msgs.incoming.maximum(:created_at)
    last_outgoing_at = msgs.outgoing.maximum(:created_at)
    return nil if last_outgoing_at.nil? # atendimento nunca falou
    return nil if last_incoming_at && last_incoming_at >= last_outgoing_at # paciente falou por último

    scope = msgs.outgoing
    scope = scope.where('created_at > ?', last_incoming_at) if last_incoming_at
    scope.minimum(:created_at)
  end

  # Estado POR ROBÔ (formato novo: {'bots' => {bot_id => {...}}}) — dois robôs
  # ativos não apagam mais o marcador um do outro. Migra o formato antigo.
  #
  # 'sent' (etapas por silêncio) zera quando a âncora muda (paciente respondeu
  # → nova cadência). 'stage_sent' (etapas por entrada na coluna) zera só
  # quando o card ENTRA DE NOVO na coluna — resposta do paciente não redispara.
  def followup_state(conversation, bot, anchor, stage_entered)
    stored = conversation.additional_attributes&.dig('cevico_followup') || {}
    stored = { 'bots' => { stored['bot_id'].to_s => stored } } if stored['bot_id'].present? # legado
    mine = stored.dig('bots', bot.id.to_s) || {}
    stage_key = stage_entered&.iso8601

    {
      'sent' => mine['anchor'] == anchor.iso8601 ? Array(mine['sent']) : [],
      'stage_sent' => mine['stage_key'] == stage_key ? Array(mine['stage_sent']) : [],
      'stage_key' => stage_key
    }
  end

  def persist_state(conversation, bot, anchor, state)
    # merge atômico: relê dentro da trava e grava só a entrada DESTE robô, sem
    # apagar o estado de outro robô nem a chave de pausa do Atendente Instagram
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      stored = attrs['cevico_followup'] || {}
      stored = { 'bots' => { stored['bot_id'].to_s => stored } } if stored['bot_id'].present? # legado
      stored['bots'] ||= {}
      stored['bots'][bot.id.to_s] = {
        'anchor' => anchor.iso8601, 'sent' => state['sent'],
        'stage_key' => state['stage_key'], 'stage_sent' => state['stage_sent']
      }
      attrs.merge('cevico_followup' => stored)
    end
  end

  def send_nudge(bot, conversation, step)
    attrs = { cevico_followup_bot_id: bot.id }
    # etapa de MENSAGEM MODELO: envia o template oficial (funciona fora da
    # janela de 24h do WhatsApp — ideal para cadências em dias)
    attrs[:template_params] = render_template_params(step['template_params'], conversation) if step['template_params'].present?

    conversation.messages.create!(
      account_id: bot.account_id,
      inbox_id: conversation.inbox_id, # robô por coluna envia na caixa da própria conversa
      message_type: :outgoing,
      content: render_message(step['message'], conversation),
      sender: bot.sender,
      additional_attributes: attrs
    )
  end

  # [nome] → primeiro nome do paciente, LIMPO: sem emojis/números/símbolos
  # (nomes de WhatsApp vêm sujos). Sem nome aproveitável → "oi" no lugar,
  # evitando "Oi oi" quando a mensagem já cumprimenta antes.
  def render_message(text, conversation)
    name = sanitized_first_name(conversation.contact)
    out = text.to_s.gsub(/\[nome\]/i) { name.presence || 'oi' }
    out = out.gsub(/\b(oi|olá|ola|opa)([\s,]+)oi\b/i, '\1') if name.blank?
    out.gsub(/ {2,}/, ' ')
  end

  def sanitized_first_name(contact)
    raw = contact&.name.to_s
    cleaned = raw.gsub(/[^\p{L}\p{M}\s'-]/, ' ').squish # só letras (emoji/nº fora)
    first = cleaned.split.first.to_s
    return '' if first.length < 2 # sobra de símbolo/letra solta não é nome

    first.capitalize
  end

  # substitui [nome] também nos parâmetros preenchidos do modelo
  def render_template_params(params, conversation)
    JSON.parse(render_message(params.to_json, conversation))
  rescue JSON::ParserError
    params
  end

  # ── registro de atividade ──
  def step_label(step)
    value = step['delay_value'].presence || step['delay_hours']
    unit = { 'minutes' => 'min', 'days' => 'd' }.fetch(step['delay_unit'], 'h')
    "cutucada de #{value}#{unit}"
  end

  def event_for(conversation, type, note: nil)
    {
      'at' => Time.current.iso8601,
      'type' => type,
      'conversation_id' => conversation.display_id,
      'contact' => conversation.contact&.name.to_s.truncate(40),
      'note' => note
    }.compact
  end

  def record_run(bot, status:, candidates: 0, sent: 0, reasons: {}, events: [])
    log = bot.activity_log.presence || {}
    log['last_run'] = {
      'at' => Time.current.iso8601, 'status' => status,
      'candidates' => candidates, 'sent' => sent, 'reasons' => reasons.to_h
    }
    log['events'] = (Array(events) + Array(log['events'])).first(EVENTS_CAP)
    bot.update_columns(activity_log: log, last_run_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
