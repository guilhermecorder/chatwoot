# Roda a cada 2 min (schedule.yml). Para cada robô ativo, procura conversas
# em que o PACIENTE ficou em silêncio (última mensagem foi do atendimento) e
# envia as "cutucadas" da cadência conforme o tempo decorrido.
#
# Âncora = primeira mensagem outgoing depois da última mensagem do paciente.
# Assim, enviar uma cutucada (nova outgoing) NÃO reinicia o cronômetro.
# Se o paciente responder (nova incoming), a âncora deixa de existir e o
# marcador é limpo — a cadência para sozinha.
#
# ESPAÇAMENTO (rodada 158): entre uma etapa e a seguinte vale a DIFERENÇA de
# prazo da cadência, contada da cutucada anterior realmente enviada. Etapa
# que venceu com o envio fechado (noite) não sai "empilhada" na abertura da
# janela junto com a seguinte — caso real de 12/09: 08:00 e 08:30 no mesmo
# paciente, só o piso de 30 min separando.
#
# Cada robô guarda seu REGISTRO DE ATIVIDADE (activity_log): resumo da última
# rodada com os motivos de cada conversa não cutucada + histórico dos envios.
# O painel da conversa mostra a PREVISÃO por conversa (#forecast): a mesma
# decisão do robô, sem enviar nem gravar nada.
class Crm::FollowupBotJob < ApplicationJob # rubocop:disable Metrics/ClassLength
  # fila ALTA de propósito (missão 03/08): o sidekiq do fork processa as
  # filas em ordem ESTRITA e scheduled_jobs fica quase no fim — em produção
  # os jobs de IA seguravam a rodada por 10-30 min e a "cutucada de 15min"
  # saía meia hora depois. Este job é leve (consultas + 1 mensagem).
  queue_as :high

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  LOOKBACK = 3.days # não cutuca conversas antigas demais
  EVENTS_CAP = 60   # histórico de envios/erros guardado por robô
  # EXPEDIENTE PADRÃO: cutucada só entre 08h e 20h (SP). O admin pode mudar a
  # janela em Automações → Robôs → "Horário de envio" (até 24h por dia) —
  # agenda_config.followup_hours {start, end}. Item 147: etapa que vencia à
  # noite empilhava pro dia seguinte e perdia a janela de 24h do WhatsApp.
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
  # ── ETIQUETAS DE ENCERRAMENTO (rodada 158) ──
  # Convenção da base (a mesma da Colheitadeira): quem tem nao_perturbe ou
  # perda_* nunca recebe cutucada, de robô nenhum. O admin acrescenta as
  # suas (ex.: att_encerrado) em Automações → Robôs → "Etiquetas que
  # encerram o follow-up" (agenda_config.followup_stop_labels).
  STOP_LABELS_FIXED = %w[nao_perturbe].freeze
  STOP_LABEL_PREFIXES = %w[perda_].freeze
  NEXT_STATUSES = %w[proxima aguardando].freeze # etapas que ainda vão sair (previsão)
  # texto dos motivos (registro de atividade + previsão no painel da conversa)
  REASON_TEXT = {
    'pausado_para_paciente' => 'follow-up pausado para este paciente',
    'etiqueta_de_encerramento' => 'etiqueta de encerramento — nenhum robô cutuca',
    'etiquetas' => 'fora do filtro de etiquetas do robô',
    'paciente_falou_ultimo' => 'o paciente falou por último — a vez é do atendimento',
    'protegida_por_etiqueta' => 'etapa protegida por etiqueta (não enviada)',
    'janela_whatsapp' => 'fora da janela de 24h do WhatsApp — só mensagem modelo entrega',
    'momento_perdido' => 'etapa vencida há horas — descartada (anti-rajada)',
    'cadencia_completa' => 'cadência completa',
    'aguardando_espacamento' => 'aguardando o espaçamento da cadência',
    'aguardando_prazo' => 'aguardando o prazo da etapa',
    'trava_cadencia_completa' => 'todas as cutucadas já saíram (mensagens reais)',
    'trava_intervalo_minimo' => 'intervalo mínimo de 30 min entre cutucadas',
    'trava_teto_diario' => 'teto diário de 4 cutucadas atingido'
  }.freeze

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

  # ── PREVISÃO por conversa (painel lateral) — SÓ LEITURA ──
  # A mesma decisão que o robô tomaria agora com esta conversa: o que já
  # saiu, o que foi pulado, quando sai a próxima e por quê. Devolve texto
  # pronto em PT-BR (text), a situação (status: proxima | parado | pausado |
  # completa | desligado) e a linha do tempo das etapas.
  def forecast(bot, conversation)
    steps = bot.ordered_steps
    return { status: 'desligado', text: 'robô sem etapas', sent: 0, total: 0, timeline: [] } if steps.blank?

    @hours = send_hours(bot.account)
    now = Time.current
    plan = plan_for(bot, conversation, steps, now)
    sent = own_nudges(bot, conversation, plan[:anchor])
    timeline = forecast_timeline(steps, plan, sent, now)
    status, text = forecast_text(bot, plan, sent.size, steps.size, now)
    {
      status: status, text: text, sent: sent.size, total: steps.size,
      next_at: timeline.find { |t| NEXT_STATUSES.include?(t[:status]) }&.dig(:at),
      timeline: timeline
    }
  end

  private

  def process_bot(bot)
    unless bot.within_window? # janela "começa em / para em"
      record_run(bot, status: 'fora_da_janela')
      return
    end

    @hours = send_hours(bot.account) # janela de envio da conta (padrão 08h–20h)
    unless @hours.cover?(TZ.now.hour)
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
    # 🚧 item 231 (cerca dos parceiros): caixas dos parceiros e pacientes de
    # parceiro do hub ficam fora de qualquer robô
    partner_inboxes = Crm::PartnerGuard.partner_inbox_ids(bot.account)
    scope = scope.where.not(inbox_id: partner_inboxes) if partner_inboxes.any?
    partner_ids = Crm::PartnerGuard.excluded_contact_ids(bot.account)
    scope = scope.where.not(contact_id: partner_ids) if partner_ids.any?
    scope
  end

  # DECIDE (plan_for, só leitura) e depois AGE: marca as etapas tratadas sem
  # envio, e envia no máximo UMA cutucada por conversa por rodada.
  def process_conversation(bot, conversation, steps, run, events)
    plan = plan_for(bot, conversation, steps)
    settle_handled(bot, conversation, plan, events)

    chosen = plan[:chosen]
    return run[:reasons][plan[:reason]] += 1 if chosen.nil?

    # marca ANTES de enviar (falha segura): se o envio quebrar no meio, o
    # pior caso é PERDER uma cutucada — nunca duplicar para o paciente.
    # Só a etapa ESCOLHIDA é marcada: as outras vencidas saem nas próximas
    # rodadas, respeitando o espaçamento da cadência.
    mark_steps(plan[:state], [chosen])
    persist_state(conversation, bot, plan[:anchor], plan[:state])
    send_nudge(bot, conversation, chosen)
    run[:sent] += 1
    events << event_for(conversation, 'sent', note: step_label(chosen[:step]))
  end

  # etapas tratadas SEM envio (protegida por etiqueta, fora da janela do
  # WhatsApp, momento perdido, ressincronização): marca + grava + registra
  def settle_handled(bot, conversation, plan, events)
    handled = Array(plan[:handled])
    return if handled.empty?

    mark_steps(plan[:state], handled)
    persist_state(conversation, bot, plan[:anchor], plan[:state])
    handled.each { |d| events << event_for(conversation, 'skipped', note: d[:note]) if d[:note] }
  end

  # ── O PLANO de uma conversa (sem efeito colateral) ──
  # Devolve um Hash com: reason (por que NÃO envia agora — nil quando há
  # etapa escolhida), anchor/state (p/ persistir), pending (etapas ainda não
  # tratadas, cada uma com due_at = quando pode sair), handled (etapas que
  # devem ser marcadas como tratadas SEM enviar, com a nota do registro),
  # chosen (a etapa que sai agora) e wait (a próxima etapa em espera).
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def plan_for(bot, conversation, steps, now = Time.current)
    plan = { handled: [], chosen: nil, wait: nil, pending: [] }
    # TRAVA individual: atendente pausou o follow-up para este paciente
    # (botão na janelinha da conversa) — nenhum robô cutuca
    return plan.merge(reason: 'pausado_para_paciente') if paused_for_patient?(conversation)
    # 🚧 item 231: paciente de parceiro do hub — nenhum robô cutuca
    return plan.merge(reason: 'paciente_de_parceiro') if Crm::PartnerGuard.partner_conversation?(conversation)
    # etiqueta de encerramento (nao_perturbe / perda_* / lista da conta) — nenhum robô cutuca
    return plan.merge(reason: 'etiqueta_de_encerramento') if stop_label?(bot.account, conversation)
    return plan.merge(reason: 'etiquetas') unless labels_match?(bot, conversation)

    anchor = silence_anchor(conversation)
    # paciente falou por último → quem deve responder é o atendimento, não o robô
    return plan.merge(reason: 'paciente_falou_ultimo') if anchor.nil?

    stage_entered = stage_entry_at(bot, conversation) # nil se não for robô de coluna
    state = followup_state(conversation, bot, anchor, stage_entered)
    pending = pending_steps(bot, conversation, steps, state, anchor, stage_entered, now)
    plan.merge!(anchor: anchor, state: state, pending: pending)

    due, waiting = pending.partition { |d| d[:overdue] >= 0 }
    plan[:wait] = waiting.min_by { |d| d[:due_at] }

    # Regras de etiqueta POR ETAPA (item 127): etapa vencida cuja etiqueta
    # protege ESTE paciente é tratada SEM enviar — a cadência segue viva e as
    # etapas seguintes (ex.: as longas) continuam valendo normalmente.
    blocked, due = due.partition { |d| step_blocked_by_labels?(d[:step], conversation) }
    blocked.each { |d| plan[:handled] << d.merge(note: "#{step_label(d[:step])} não enviada — protegida por etiqueta") }

    # Texto simples FORA da janela de 24h do WhatsApp não entrega (a Meta
    # recusa; ficava uma mensagem "falhou" na conversa). Tratada sem enviar
    # e avisada no registro — etapa de mensagem modelo segue valendo.
    unreachable, due = due.partition { |d| text_step?(d[:step]) && !can_reply?(conversation) }
    unreachable.each do |d|
      plan[:handled] << d.merge(note: "#{step_label(d[:step])} não enviada — fora da janela de 24h do WhatsApp (só mensagem modelo entrega)")
    end

    # Só o que venceu há HORAS (deploy/queda longa) perde o momento — é
    # marcado como tratado SEM enviar. As demais vencidas NÃO são absorvidas
    # (fix 03/08): sai UMA por rodada, na ORDEM da cadência.
    stale, fresh = due.partition { |d| d[:overdue] > STALE_HOURS }
    stale.each { |d| plan[:handled] << d.merge(note: "#{step_label(d[:step])} venceu há #{d[:overdue].round}h — não enviada") }

    return plan.merge(reason: no_send_reason(stale, unreachable, blocked, plan)) if fresh.empty?

    # ANTI-RAJADA: no máximo UMA cutucada por conversa por rodada — a mais
    # antiga da cadência entre as vencidas (ordem das mensagens preservada)
    chosen = fresh.min_by { |d| Crm::FollowupBot.step_delay_hours(d[:step]) }
    plan[:total] = steps.size
    apply_physical_locks(plan, conversation, chosen, fresh, now)
  end

  # por que nada sai nesta rodada (na ordem do que aconteceu)
  def no_send_reason(stale, unreachable, blocked, plan)
    return 'momento_perdido' if stale.any?
    return 'janela_whatsapp' if unreachable.any?
    return 'protegida_por_etiqueta' if blocked.any?
    return 'cadencia_completa' if plan[:pending].empty?

    plan[:wait][:spacing] ? 'aguardando_espacamento' : 'aguardando_prazo'
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # ── TRAVA FÍSICA: consulta as cutucadas REALMENTE enviadas (tabela de
  # mensagens) antes de qualquer envio. Protege o paciente mesmo que o
  # marcador tenha sido apagado/corrompido por outro processo.
  def apply_physical_locks(plan, conversation, chosen, fresh, now) # rubocop:disable Metrics/AbcSize
    nudges = bot_nudges(conversation)
    if nudges.where('created_at >= ?', plan[:anchor]).count >= plan[:total]
      # cadência já saiu inteira nas mensagens → ressincroniza o marcador (sem evento)
      fresh.each { |d| plan[:handled] << d.merge(note: nil) }
      return plan.merge(reason: 'trava_cadencia_completa')
    end

    last_nudge_at = nudges.maximum(:created_at)
    if last_nudge_at && last_nudge_at > now - MIN_GAP_MINUTES.minutes
      return hold(plan, chosen, last_nudge_at + MIN_GAP_MINUTES.minutes, 'trava_intervalo_minimo')
    end

    if nudges.where('created_at >= ?', TZ.now.beginning_of_day).count >= DAILY_CAP
      return hold(plan, chosen, next_send_moment(TZ.now.beginning_of_day + 1.day), 'trava_teto_diario')
    end

    plan.merge(chosen: chosen)
  end

  # etapa escolhida segurada por uma trava: vira a "próxima", com a hora da
  # nova tentativa (aparece na previsão do painel da conversa)
  def hold(plan, chosen, retry_at, reason)
    held = chosen.merge(due_at: retry_at)
    plan[:pending] = plan[:pending].map { |d| d[:index] == chosen[:index] ? held : d }
    plan.merge(reason: reason, wait: held)
  end

  # Etapas ainda não tratadas, cada uma com o momento em que PODE sair
  # (due_at) e o atraso em relação a ele (overdue em horas; negativo = ainda
  # não chegou). due_at considera, nesta ordem:
  #  1. o prazo da etapa desde a base (âncora do silêncio ou entrada na coluna);
  #  2. o ESPAÇAMENTO: a diferença de prazo para a etapa anterior, contada da
  #     última cutucada real deste robô — etapa que venceu com o envio
  #     fechado não sai colada na seguinte quando a janela reabre;
  #  3. a janela de envio da conta: fora dela, espera reabrir (nada é
  #     descartado por vencer de madrugada — fix 03/08).
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists
  def pending_steps(bot, conversation, steps, state, anchor, stage_entered, now)
    delays = steps.map { |s| Crm::FollowupBot.step_delay_hours(s) }
    steps.each_with_index.filter_map do |step, index|
      from_stage = step['delay_from'] == 'stage_entry'
      # etapas "desde a entrada na coluna" têm marcador PRÓPRIO, amarrado à
      # entrada na coluna — resposta do paciente não as redispara.
      next if (from_stage ? state['stage_sent'] : state['sent']).include?(index)

      base_time = from_stage ? stage_entered : anchor
      next if base_time.nil?

      due_at = base_time + delays[index].hours
      spacing = false
      if index.positive? && (last_at = own_last_nudge_at(bot, conversation))
        spaced = last_at + [delays[index] - delays[index - 1], 0].max.hours
        if spaced > due_at
          due_at = spaced
          spacing = true
        end
      end
      send_at = next_send_moment(due_at)
      { step: step, index: index, from_stage: from_stage, due_at: send_at, spacing: spacing,
        overdue: (now - send_at) / 3600.0 }
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists

  # quando um momento cai FORA da janela de envio, o envio fica para a
  # próxima abertura (hoje, se ainda não abriu; senão amanhã). Dentro da
  # janela devolve o próprio momento.
  def next_send_moment(time)
    hours = @hours || BUSINESS_HOURS
    local = time.in_time_zone(TZ)
    return time if hours.cover?(local.hour)

    (local.hour < hours.first ? local : local + 1.day).change(hour: hours.first)
  end

  # cutucadas de QUALQUER robô de follow-up nesta conversa (mensagens reais)
  def bot_nudges(conversation)
    conversation.messages.outgoing
                .where("additional_attributes ->> 'cevico_followup_bot_id' IS NOT NULL")
  end

  def own_nudges_scope(bot, conversation)
    bot_nudges(conversation).where("additional_attributes ->> 'cevico_followup_bot_id' = ?", bot.id.to_s)
  end

  # última cutucada REAL deste robô nesta conversa (base do espaçamento) —
  # uma consulta por conversa por rodada
  def own_last_nudge_at(bot, conversation)
    @own_last_nudge ||= {}
    key = "#{bot.id}:#{conversation.id}"
    return @own_last_nudge[key] if @own_last_nudge.key?(key)

    @own_last_nudge[key] = own_nudges_scope(bot, conversation).maximum(:created_at)
  end

  # cutucadas REAIS deste robô nesta cadência (desde a âncora), com o nº da
  # etapa quando a mensagem o carrega (cevico_followup_step, rodada 158)
  def own_nudges(bot, conversation, anchor)
    return [] if anchor.nil?

    own_nudges_scope(bot, conversation)
      .where('created_at >= ?', anchor)
      .pluck(:created_at, Arel.sql("additional_attributes ->> 'cevico_followup_step'"))
      .map { |at, idx| { at: at, index: idx.present? ? idx.to_i : nil } }
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

  # ── configuração da conta (uma leitura por conta por rodada) ──
  def agenda_config(account)
    @agenda_config_cache ||= {}
    @agenda_config_cache[account.id] ||= CrmSetting.find_by(account_id: account.id)&.agenda_config || {}
  end

  # Janela de envio da CONTA (Automações → Robôs → "Horário de envio"):
  # padrão 08h–20h; 0–24 = envia a qualquer hora do dia. Config inválida
  # (start >= end, lixo) cai no padrão — o robô nunca fica sem janela.
  def send_hours(account)
    @send_hours_cache ||= {}
    @send_hours_cache[account.id] ||= begin
      cfg = agenda_config(account)['followup_hours'] || {}
      h_start = cfg.key?('start') ? cfg['start'].to_i.clamp(0, 23) : BUSINESS_HOURS.first
      h_end = cfg.key?('end') ? cfg['end'].to_i.clamp(1, 24) : BUSINESS_HOURS.last
      h_start < h_end ? (h_start...h_end) : BUSINESS_HOURS
    end
  end

  # etiquetas de encerramento configuradas pelo admin (além das fixas)
  def stop_labels(account)
    @stop_labels_cache ||= {}
    @stop_labels_cache[account.id] ||= Array(agenda_config(account)['followup_stop_labels'])
                                       .map { |l| l.to_s.strip.downcase }.reject(&:blank?)
  end

  def paused_for_patient?(conversation)
    conversation.contact&.additional_attributes&.[]('cevico_followup_paused').present?
  end

  # contato OU conversa com etiqueta de encerramento → nenhum robô cutuca
  def stop_label?(account, conversation)
    labels = all_labels_for(conversation).map(&:downcase)
    return false if labels.empty?
    return true if labels.intersect?(STOP_LABELS_FIXED)
    return true if labels.any? { |l| STOP_LABEL_PREFIXES.any? { |p| l.start_with?(p) } }

    labels.intersect?(stop_labels(account))
  end

  # Filtros "tem / não tem": só cutuca quem TEM todas as etiquetas exigidas
  # e NÃO TEM nenhuma das excluídas. Olha as etiquetas do CONTATO **e** da
  # CONVERSA (item 127: a cadeia automática etiqueta a conversa primeiro —
  # olhar só o contato deixava a proteção furada).
  def labels_match?(bot, conversation)
    return false if conversation.contact.blank?

    required = Array(bot.required_labels).map(&:to_s)
    excluded = Array(bot.exclude_labels).map(&:to_s)
    return true if required.empty? && excluded.empty?

    labels = all_labels_for(conversation)
    return false if required.any? && (required - labels).any?
    return false if excluded.any? && labels.intersect?(excluded)

    true
  end

  # Regras de etiqueta POR ETAPA: skip_labels = pula quem TEM alguma;
  # only_labels = só envia para quem TEM alguma. Vazias = etapa para todos.
  def step_blocked_by_labels?(step, conversation)
    skip = Array(step['skip_labels']).map(&:to_s)
    only = Array(step['only_labels']).map(&:to_s)
    return false if skip.empty? && only.empty?

    labels = all_labels_for(conversation)
    return true if skip.any? && labels.intersect?(skip)
    return true if only.any? && !labels.intersect?(only)

    false
  end

  # etiquetas do contato + da conversa, uma vez por conversa por rodada
  def all_labels_for(conversation)
    @all_labels_for ||= {}
    @all_labels_for[conversation.id] ||=
      (Array(conversation.contact&.label_list) + Array(conversation.label_list)).map(&:to_s).uniq
  end

  def text_step?(step)
    step['template_params'].blank?
  end

  # janela de resposta do canal (core: Conversations::MessageWindowService —
  # WhatsApp/Instagram = 24h desde a última mensagem do paciente). Caixa sem
  # janela devolve true. Uma consulta por conversa por rodada.
  def can_reply?(conversation)
    @can_reply ||= {}
    return @can_reply[conversation.id] if @can_reply.key?(conversation.id)

    @can_reply[conversation.id] = conversation.can_reply?
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

    # 🔴 o .dup é OBRIGATÓRIO — sem ele, o << do mark_steps mutava o MESMO
    # array que vive no additional_attributes carregado, o with_lock do
    # merge atômico recusava o registro "sujo" e a rodada caía em erro TODA
    # VEZ após a 1ª cutucada (só o primeiro follow-up saía — bug de produção
    # 03/08; mesma lição do item 98: deep_dup antes do lock)
    {
      'sent' => mine['anchor'] == anchor.iso8601 ? Array(mine['sent']).dup : [],
      'stage_sent' => mine['stage_key'] == stage_key ? Array(mine['stage_sent']).dup : [],
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

  def send_nudge(bot, conversation, chosen)
    step = chosen[:step]
    # cada cutucada carrega o robô E o nº da etapa (linha do tempo da previsão)
    attrs = { cevico_followup_bot_id: bot.id, cevico_followup_step: chosen[:index] }
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

  # ── previsão: linha do tempo das etapas ──
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def forecast_timeline(steps, plan, sent, now)
    marks = plan[:state] ? (Array(plan[:state]['sent']) + Array(plan[:state]['stage_sent'])) : []
    legacy = sent.reject { |n| n[:index] }.sort_by { |n| n[:at] } # cutucadas antigas sem nº da etapa
    pending = Array(plan[:pending]).index_by { |d| d[:index] }
    handled = Array(plan[:handled]).index_by { |d| d[:index] }

    steps.each_with_index.map do |step, i|
      entry = { label: step_label(step) }
      nudge = sent.find { |n| n[:index] == i } || (marks.include?(i) ? legacy.shift : nil)
      if nudge
        entry.merge(status: 'enviada', at: nudge[:at].iso8601, when: fmt_when(nudge[:at], now))
      elsif marks.include?(i)
        entry.merge(status: 'pulada', note: 'tratada sem envio')
      elsif handled[i]
        entry.merge(status: 'pulada', note: handled[i][:note] || 'tratada sem envio')
      elsif plan[:chosen] && plan[:chosen][:index] == i
        at = next_send_moment(now)
        entry.merge(status: 'proxima', at: at.iso8601, when: at > now + 3.minutes ? fmt_when(at, now) : 'agora')
      elsif pending[i]
        entry.merge(status: 'aguardando', at: pending[i][:due_at].iso8601, when: fmt_when(pending[i][:due_at], now),
                    note: pending[i][:spacing] ? 'espaçamento da cadência' : nil).compact
      else
        entry.merge(status: 'pendente')
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def forecast_text(bot, plan, sent, total, now)
    tail = " · #{sent} de #{total} enviadas"
    return ['desligado', "robô desligado#{tail}"] unless bot.active
    return ['parado', "fora da janela \"começa em / para em\" do robô#{tail}"] unless bot.within_window?(now)

    reason = plan[:reason]
    if plan[:chosen]
      at = next_send_moment(now)
      moment = at <= now + 3.minutes ? 'na próxima rodada (até 2 min)' : "#{fmt_when(at, now)} — abertura do horário de envio"
      ['proxima', "próxima: #{step_label(plan[:chosen][:step])} #{moment}#{tail}"]
    elsif %w[cadencia_completa trava_cadencia_completa].include?(reason)
      ['completa', "cadência completa#{tail}"]
    elsif reason == 'pausado_para_paciente'
      ['pausado', REASON_TEXT[reason]]
    elsif plan[:wait]
      w = plan[:wait]
      why = ''
      why = ' (espaçamento da cadência)' if w[:spacing]
      why = " (#{REASON_TEXT[reason]})" if reason.to_s.start_with?('trava_')
      ['proxima', "próxima: #{step_label(w[:step])} #{fmt_when(w[:due_at], now)}#{why}#{tail}"]
    else
      ['parado', "#{REASON_TEXT.fetch(reason, reason.to_s)}#{tail}"]
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # "hoje 15:00" / "amanhã 08:00" / "ontem 18:52" / "12/09 18:52"
  def fmt_when(time, now)
    t = time.in_time_zone(TZ)
    today = now.in_time_zone(TZ).to_date
    day = { 0 => 'hoje', 1 => 'amanhã', -1 => 'ontem' }[(t.to_date - today).to_i] || t.strftime('%d/%m')
    "#{day} #{t.strftime('%H:%M')}"
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
