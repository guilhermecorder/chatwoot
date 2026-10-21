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
  # ── ETAPA DE IA (item 315) ──
  # teto de chamadas à IA por rodada: a rodada tem a trava de 10 min e cada
  # chamada leva segundos — o que sobrar sai na rodada seguinte (2 min), sem
  # marcar nada. Erro passageiro da IA (timeout, 529) tenta de novo até
  # AI_MAX_TRIES vezes; erro de configuração (sem chave) não repete.
  AI_PER_ROUND = 15
  AI_MAX_TRIES = 3
  # ── FOLLOW-UP INTELIGENTE (13/10) — Crm::FollowupClosure / Crm::FollowupConversationReader ──
  # Antes da 1ª cutucada de cada silêncio o robô LÊ a conversa (aberta,
  # encerrada, adiada, recusou) e só cutuca quem ficou com algo a responder.
  # Config da conta em agenda_config.followup_smart (Automações → Robôs).
  READS_PER_ROUND = 25          # leituras por rodada; o resto lê na próxima (2 min)
  COLD_MAX_HOURS = 24           # lead que nunca escreveu: 1 cutucada, dentro de 24h
  REACTIVATIONS_PER_ROUND = 20  # "adiou" → mensagem modelo dias depois
  REACTIVATION_STALE_DAYS = 3   # reativação que passou do dia há mais que isso não sai
  SMART_DEFAULTS = {
    'leitura' => true, 'fim_de_semana' => true, 'lead_frio' => true,
    'reativacao' => { 'ativa' => true, 'dias' => 7, 'modelos' => {} }
  }.freeze
  # ── ETIQUETAS DE ENCERRAMENTO (rodada 158) ──
  # Convenção da base (a mesma da Colheitadeira): quem tem nao_perturbe ou
  # perda_* nunca recebe cutucada, de robô nenhum. O admin acrescenta as
  # suas (ex.: att_encerrado) em Automações → Robôs → "Etiquetas que
  # encerram o follow-up" (agenda_config.followup_stop_labels).
  # ── 🚦 RITMO DE ENVIO POR NÚMERO (item 345, 14/10) ──
  # Tudo o que vencia de madrugada ia para as 08:00 e saía DE UMA VEZ —
  # dezenas de mensagens do mesmo número no mesmo minuto parecem SPAM para a
  # Meta. Agora cada caixa (número) manda no máximo N cutucadas em qualquer
  # janela de M minutos (padrão: 5 a cada 5), somando TODOS os robôs e a
  # reativação de quem adiou. A rodada vira UMA fila: quem tem a janela de
  # 24h do WhatsApp mais perto de fechar sai primeiro. Quem passou do teto
  # espera a próxima rodada SEM ser marcado (a etapa continua valendo).
  # Config: agenda_config.followup_pace {per_window, minutes} (Automações →
  # Robôs, ao lado do "Horário de envio"); per_window 0 = sem limite.
  PACE_DEFAULTS = { 'per_window' => 5, 'minutes' => 5 }.freeze
  PACE_LIMITS = { 'per_window' => (0..100), 'minutes' => (1..120) }.freeze
  PACE_HOLD_TTL = 24.hours # quanto tempo a etapa "na fila do ritmo" fica livre do descarte por atraso
  PACE_SLICE = 100         # conversas carregadas por vez ao andar na fila da rodada
  WINDOW_HOURS = 24        # janela de atendimento do WhatsApp (prioridade da fila)
  # mensagens que contam no ritmo: cutucadas de qualquer robô + reativações
  PACE_MESSAGES_SQL = "(messages.additional_attributes ->> 'cevico_followup_bot_id' IS NOT NULL " \
                      "OR messages.additional_attributes ->> 'cevico_followup_reativacao' = 'true')".freeze
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
    'trava_teto_diario' => 'teto diário de 4 cutucadas atingido',
    'ia_sem_texto' => 'a IA não escreveu o texto (chave/serviço) — etapa tratada sem envio',
    'ia_fila' => 'teto de chamadas à IA nesta rodada — sai na próxima',
    # 🧠 follow-up inteligente (13/10)
    'conversa_encerrada' => 'conversa encerrada — o robô não cutuca',
    'conversa_adiada' => 'paciente adiou — volta com mensagem modelo dias depois',
    'conversa_recusou' => 'paciente recusou — o robô parou',
    'atendente_encerrou' => 'o Atendente de IA se despediu — o robô não cutuca',
    'leitura_fila' => 'leitura da conversa na fila — sai na próxima rodada',
    'lead_frio' => 'lead que nunca escreveu: só 1 cutucada em 24h',
    'entrega_falhou' => 'a última cutucada não foi entregue (possível bloqueio) — o robô parou',
    'fim_de_semana' => 'fim de semana: só cutuca quem escreveu no mesmo dia',
    # 🚦 item 345
    'ritmo' => 'na fila do ritmo de envio (limite de mensagens por número) — sai nas próximas rodadas'
  }.freeze

  # 🚦 item 345: ritmo de envio normalizado — o controlador grava por aqui
  # também. Campo ausente, inválido ou fora da faixa → padrão (5 a cada 5 min);
  # per_window 0 = sem limite.
  def self.pace_config(raw)
    cfg = raw.is_a?(Hash) ? raw.stringify_keys : {}
    PACE_DEFAULTS.to_h do |key, default|
      value = cfg[key].to_s.strip.match?(/\A\d+\z/) ? cfg[key].to_s.to_i : nil
      [key, value && PACE_LIMITS[key].cover?(value) ? value : default]
    end
  end

  def perform
    # TRAVA: cron a cada 2 min. Se uma rodada demora mais que isso (muitas
    # conversas abertas), a seguinte começava por cima e podia cutucar o mesmo
    # paciente 2× antes do persist_state. O lock faz a rodada nova pular.
    lock_manager = Redis::LockManager.new
    lock_key = 'CRM_FOLLOWUP_BOT_JOB_LOCK'
    return unless lock_manager.lock(lock_key, 10.minutes)

    begin
      @reads = 0 # 🧠 leituras da conversa nesta rodada (teto READS_PER_ROUND)
      # 🚦 item 345: todos os robôs numa fila só (ritmo por número vale para a rodada inteira)
      process_bots(Crm::FollowupBot.active.includes(:inbox).order(:id).to_a)
      process_reactivations # 🧠 quem adiou: mensagem modelo dias depois (decisão B, 13/10) — mesmo ritmo
      Crm::CronHealth.ran!('followup') # 🚨 #217: sinal de vida da rodada (o vigia confere)
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  # ── PREVISÃO por conversa (painel lateral) — SÓ LEITURA ──
  # A mesma decisão que o robô tomaria agora com esta conversa: o que já
  # saiu, o que foi pulado, quando sai a próxima e por quê. Devolve texto
  # pronto em PT-BR (text), a situação (status: proxima | parado | pausado |
  # completa | desligado) e a linha do tempo das etapas.
  def forecast(bot, conversation) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    steps = bot.ordered_steps
    return { status: 'desligado', text: 'robô sem etapas', sent: 0, total: 0, timeline: [] } if steps.blank?

    @hours = send_hours(bot.account)
    now = Time.current
    plan = plan_for(bot, conversation, steps, now)
    sent = own_nudges(bot, conversation, plan[:anchor])
    timeline = forecast_timeline(steps, plan, sent, now)
    status, text = forecast_text(bot, plan, sent.size, steps.size, now)
    # 🧠 a 1ª cutucada do silêncio só sai depois da leitura da conversa
    text = "#{text} · antes, lê a conversa para ver se ainda está aberta" if status == 'proxima' && plan[:leitura_pendente]
    if ai_without_key?(bot, plan) # item 315: etapa de IA sem chave e sem reserva não sai
      status = 'parado'
      text = "#{REASON_TEXT['ia_sem_texto']} · #{sent.size} de #{steps.size} enviadas"
    end
    text = pace_forecast(bot, conversation, timeline, text) if status == 'proxima' && plan[:chosen]
    {
      status: status, text: text, sent: sent.size, total: steps.size,
      next_at: timeline.find { |t| NEXT_STATUSES.include?(t[:status]) }&.dig(:at),
      timeline: timeline
    }
  end

  # conversas em que ESTE robô atua (caixas, colunas, cerca dos parceiros) —
  # usado também pela prévia da etapa de IA (controlador)
  def candidates(bot)
    conversations(bot)
  end

  private

  def ai_without_key?(bot, plan)
    step = plan[:chosen]&.dig(:step)
    return false unless step && Crm::FollowupBot.ai_step?(step) && step['message'].blank?

    CrmSetting.find_by(account: bot.account)&.ai_config&.dig('api_key').blank?
  end

  # um robô sozinho (specs e chamadas avulsas) = uma rodada com só ele
  def process_bot(bot)
    process_bots([bot])
  end

  # 🚦 item 345: a rodada junta as conversas de TODOS os robôs numa FILA só,
  # ordenada pela janela de 24h do WhatsApp (#priority_queue), e anda nela uma
  # a uma — assim o ritmo por número vale para a rodada inteira e quem tem
  # menos tempo para conversar passa na frente. Cada robô continua com o seu
  # registro de atividade (motivos, envios) e o seu teto de IA.
  def process_bots(bots)
    @pace_base = {}            # já enviado por caixa nos últimos M min (lido 1× por caixa na rodada)
    @pace_sent = Hash.new(0)   # enviado por caixa NESTA rodada
    work = bots.filter_map { |bot| prepare_bot(bot) }
    priority_queue(work).each_slice(PACE_SLICE) { |slice| process_slice(slice) }
    work.each { |item| finish_bot(item) }
  end

  # confere janela/horário/etapas do robô e lista as conversas candidatas;
  # nil quando o robô não roda nesta rodada (já registrado)
  def prepare_bot(bot) # rubocop:disable Metrics/MethodLength
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
    if steps.blank?
      record_run(bot, status: 'sem_etapas')
      return
    end

    # UMA conversa por contato: a de última atividade (caixa prioritária) —
    # evita cutucar o mesmo paciente em várias caixas de entrada ao mesmo tempo.
    ids = conversations(bot)
          .select('DISTINCT ON (conversations.contact_id) conversations.id')
          .order('conversations.contact_id, conversations.last_activity_at DESC')
          .map(&:id).sort
    # ai_calls: item 315 — chamadas à IA deste robô nesta rodada (teto AI_PER_ROUND)
    { bot: bot, steps: steps, ids: ids, ai_calls: 0, events: [],
      run: { status: 'ok', candidates: ids.size, sent: 0, reasons: Hash.new(0) } }
  end

  # 🚦 a FILA da rodada: pares [robô, conversa]. Primeiro quem está com a
  # janela de 24h do WhatsApp aberta, da última fala do paciente mais ANTIGA
  # (janela fechando antes) para a mais nova; depois quem não tem janela
  # aberta (lead que nunca escreveu, paciente sumido há mais de 24h — só
  # mensagem modelo entrega), na ordem de antes (robô, nº da conversa).
  def priority_queue(work)
    pairs = work.flat_map { |item| item[:ids].map { |id| [item, id] } }
    opened = window_opened_at(pairs.map(&:last).uniq)
    pairs.each_with_index
         .sort_by { |(_, id), i| [opened[id] ? 0 : 1, opened[id].to_f, i] }
         .map(&:first)
  end

  # última fala do paciente dentro das 24h, por conversa (uma consulta)
  def window_opened_at(conversation_ids)
    return {} if conversation_ids.empty?

    Message.unscope(:order)
           .where(conversation_id: conversation_ids, message_type: :incoming, private: false)
           .where('created_at > ?', WINDOW_HOURS.hours.ago)
           .group(:conversation_id).maximum(:created_at)
  end

  # carrega um pedaço da fila (eager-load do contato + inbox: evita 1 query
  # por conversa só pra achar o contato/etiquetas). Cada robô recebe a SUA
  # instância da conversa, como antes (o estado de um não vaza no outro).
  def process_slice(slice)
    loaded = slice.group_by { |item, _| item[:bot].id }.transform_values do |pairs|
      Conversation.where(id: pairs.map(&:last)).includes(:contact, :inbox).index_by(&:id)
    end
    slice.each do |item, id|
      conversation = loaded.dig(item[:bot].id, id)
      process_candidate(item, conversation) if conversation # sumiu entre a busca e agora: pula
    end
  end

  def process_candidate(item, conversation)
    bot = item[:bot]
    @hours = send_hours(bot.account)
    @ai_calls = item[:ai_calls]
    process_conversation(bot, conversation, item[:steps], item[:run], item[:events])
  rescue StandardError => e
    item[:run][:reasons]['erro'] += 1
    item[:events] << event_for(conversation, 'error', note: e.message.truncate(120))
    Rails.logger.error("[CEVICO followup] conversa #{conversation.id}: #{e.message}")
    # 🚨 #217: registra (rastreador 1×/h por conversa) sem marcar o robô inteiro
    Crm::CronHealth.failed!('followup', e, account: bot.account, item: "conversa #{conversation.id}", count: false)
  ensure
    item[:ai_calls] = @ai_calls.to_i
  end

  def finish_bot(item)
    run = item[:run]
    # rodada "com erro" só quando metade ou mais das conversas falharam (1 conversa
    # com dado ruim não deixa o robô "com erro" para sempre)
    Crm::CronHealth.mark_round_error!('followup', failed: run[:reasons]['erro'], tried: item[:ids].size)
    record_run(item[:bot], **run, events: item[:events])
  end

  def conversations(bot)
    scope = bot.account.conversations
               .where(status: :open)
               .where('conversations.last_activity_at >= ?', LOOKBACK.ago)

    # item 315: colunas do CRM em que o robô atua (robô de coluna = a dele;
    # robô global = as marcadas; nenhuma = qualquer coluna, com ou sem card)
    stage_ids = bot.acting_stage_ids
    if stage_ids.any?
      contact_ids = Crm::Contact.where(stage_id: stage_ids).select(:contact_id)
      scope = scope.where(contact_id: contact_ids)
    end
    # caixas em que atua: nenhuma marcada = todas as conversas abertas — a
    # mensagem sai pelo número da própria conversa
    inbox_ids = bot.acting_inbox_ids
    scope = scope.where(inbox_id: inbox_ids) if inbox_ids.any?
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
  def process_conversation(bot, conversation, steps, run, events) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
    plan = plan_for(bot, conversation, steps)
    settle_handled(bot, conversation, plan, events)

    chosen = plan[:chosen]
    return run[:reasons][plan[:reason]] += 1 if chosen.nil?

    # 🚦 item 345: o número desta conversa já mandou o teto do ritmo — espera a
    # vez na próxima rodada SEM marcar nada (nem mark_steps nem persist_state);
    # fica só o lembrete "na fila" que protege a etapa do descarte por atraso.
    # Vem antes da leitura e da IA: não gasta chamada com quem nem pode sair agora.
    if pace_full?(bot.account, conversation.inbox_id)
      remember_pace_hold(bot, conversation, chosen)
      return run[:reasons]['ritmo'] += 1
    end

    # item 315: etapa de IA além do teto da rodada fica para a próxima (sem marcar)
    return run[:reasons]['ia_fila'] += 1 if ai_queue_full?(chosen)

    # 🧠 follow-up inteligente: a cutucada venceu — a conversa ainda está aberta?
    # (uma leitura por silêncio; o que não for "aberta" não recebe nada)
    if plan[:leitura_pendente]
      return run[:reasons]['leitura_fila'] += 1 if @reads.to_i >= READS_PER_ROUND

      closed = read_conversation(conversation, plan)
      return record_skip(run, events, conversation, closed[:reason], closed[:note]) if closed
    end

    # marca ANTES de qualquer coisa (falha segura): se o envio — ou a IA —
    # quebrar no meio, o pior caso é PERDER uma cutucada, nunca duplicar para o
    # paciente (duas rodadas sobrepostas não cutucam a mesma conversa).
    # Só a etapa ESCOLHIDA é marcada: as outras vencidas saem nas próximas
    # rodadas, respeitando o espaçamento da cadência.
    mark_steps(plan[:state], [chosen])
    persist_state(conversation, bot, plan[:anchor], plan[:state])

    outcome = nudge_content(bot, conversation, chosen)
    if outcome[:text].nil?
      note = settle_ai_failure(bot, conversation, plan, chosen, outcome)
      return record_skip(run, events, conversation, 'ia_sem_texto', note)
    end

    send_nudge(bot, conversation, chosen, outcome[:text])
    pace_count!(conversation.inbox_id)
    run[:sent] += 1
    events << event_for(conversation, 'sent', note: step_label(chosen[:step]))
  end

  def record_skip(run, events, conversation, reason, note)
    run[:reasons][reason] += 1
    events << event_for(conversation, 'skipped', note: note)
    nil
  end

  def ai_queue_full?(chosen)
    Crm::FollowupBot.ai_step?(chosen[:step]) && @ai_calls.to_i >= AI_PER_ROUND
  end

  # texto da cutucada: etapa de IA → a IA escreve a partir da conversa (cai
  # no texto de reserva da etapa, se houver); as demais → o texto/modelo fixo.
  # Devolve { text:, config_error: } — text nil = nada para enviar.
  def nudge_content(bot, conversation, chosen)
    step = chosen[:step]
    return { text: render_message(step['message'], conversation) } unless Crm::FollowupBot.ai_step?(step)

    @ai_calls = @ai_calls.to_i + 1
    result = Crm::FollowupAiNudgeService.new(conversation: conversation, bot: bot, step: step).call
    return { text: result[:text] } if result[:text].present?

    Rails.logger.warn("[CEVICO followup] IA não escreveu (conversa #{conversation.id}): #{result[:error]}")
    reserve = step['message'].presence && render_message(step['message'], conversation)
    { text: reserve, config_error: result[:config_error] == true }
  end

  # IA sem texto e sem reserva: erro passageiro (timeout, serviço fora) desmarca
  # a etapa para tentar de novo na próxima rodada, até AI_MAX_TRIES vezes;
  # erro de configuração (sem chave) ou tentativas esgotadas = tratada sem envio
  # devolve a nota do registro
  def settle_ai_failure(bot, conversation, plan, chosen, outcome)
    tries = bump_ai_tries(plan[:state], chosen)
    retry_later = !outcome[:config_error] && tries < AI_MAX_TRIES
    unmark_steps(plan[:state], [chosen]) if retry_later
    persist_state(conversation, bot, plan[:anchor], plan[:state])
    return "#{step_label(chosen[:step])} não enviada — a IA não escreveu o texto" unless retry_later

    "#{step_label(chosen[:step])} — a IA não respondeu (tentativa #{tries}); tenta de novo na próxima rodada"
  end

  def bump_ai_tries(state, chosen)
    tries = (state['ai_tries'] ||= {})
    tries[chosen[:index].to_s] = tries[chosen[:index].to_s].to_i + 1
  end

  def unmark_steps(state, due)
    due.each do |d|
      list = d[:from_stage] ? state['stage_sent'] : state['sent']
      list.delete(d[:index])
    end
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

    # 🧠 follow-up inteligente: entrega falhou, conversa já lida como
    # encerrada/adiada/recusou, carimbo de despedida do Atendente, lead frio
    smart_check = closure_check(bot, conversation, anchor)
    return plan.merge(smart_check) if smart_check[:reason]

    plan.merge!(smart_check)
    stage_entered = stage_entry_at(bot, conversation) # nil se não for robô de coluna
    state = followup_state(conversation, bot, anchor, stage_entered)
    pending = pending_steps(bot, conversation, steps, state, anchor, stage_entered, now)
    pending = cold_lead_steps(pending, steps) if plan[:cold]
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
    # 🚦 item 345: etapa que estava NO PRAZO quando o ritmo de envio a segurou
    # (lembrete "na fila" no Redis, #remember_pace_hold) não é descartada por
    # atraso — a demora é da fila do número, não de queda/deploy. Escolhemos
    # ISENTAR (em vez de recalcular o atraso a partir de um momento deslocado)
    # porque a fila não tem hora certa para andar: depende de quantos estão
    # na frente. A isenção vale até PACE_HOLD_TTL (24h) depois da 1ª espera;
    # passou disso, volta a regra normal do momento perdido.
    stale, fresh = due.partition { |d| d[:overdue] > STALE_HOURS && !pace_held?(bot, conversation, d) }
    stale.each { |d| plan[:handled] << d.merge(note: "#{step_label(d[:step])} venceu há #{d[:overdue].round}h — não enviada") }

    return plan.merge(reason: no_send_reason(stale, unreachable, blocked, plan)) if fresh.empty?

    # ANTI-RAJADA: no máximo UMA cutucada por conversa por rodada — a mais
    # antiga da cadência entre as vencidas (ordem das mensagens preservada)
    chosen = fresh.min_by { |d| Crm::FollowupBot.step_delay_hours(d[:step]) }
    plan[:total] = plan[:cold] ? 1 : steps.size # 🧠 lead frio: 1 cutucada só
    apply_physical_locks(bot, plan, conversation, chosen, fresh, now)
  end

  # por que nada sai nesta rodada (na ordem do que aconteceu)
  def no_send_reason(stale, unreachable, blocked, plan)
    return 'momento_perdido' if stale.any?
    return 'janela_whatsapp' if unreachable.any?
    return 'protegida_por_etiqueta' if blocked.any?
    return (plan[:cold] ? 'lead_frio' : 'cadencia_completa') if plan[:pending].empty?
    return 'fim_de_semana' if plan[:wait][:weekend]

    plan[:wait][:spacing] ? 'aguardando_espacamento' : 'aguardando_prazo'
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # ── TRAVA FÍSICA: consulta as cutucadas REALMENTE enviadas (tabela de
  # mensagens) antes de qualquer envio. Protege o paciente mesmo que o
  # marcador tenha sido apagado/corrompido por outro processo.
  def apply_physical_locks(bot, plan, conversation, chosen, fresh, now) # rubocop:disable Metrics/AbcSize, Metrics/ParameterLists
    nudges = bot_nudges(conversation)
    # cadência completa = as cutucadas DESTE robô (as de outro robô não contam
    # contra o total deste — varredura 03/10); intervalo e teto diário seguem
    # valendo para qualquer robô
    if own_nudges_scope(bot, conversation).where('created_at >= ?', plan[:anchor]).count >= plan[:total]
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

  # ── 🧠 FOLLOW-UP INTELIGENTE (13/10) ──────────────────────────────────────
  # config da conta (Automações → Robôs → "Follow-up inteligente"), com padrões
  def smart(account)
    @smart_cache ||= {}
    @smart_cache[account.id] ||= begin
      cfg = agenda_config(account)['followup_smart'] || {}
      SMART_DEFAULTS.merge(cfg.slice(*SMART_DEFAULTS.keys)) do |key, default, value|
        next value unless key == 'reativacao'

        default.merge(value.is_a?(Hash) ? value : {})
      end
    end
  end

  # Só leitura: devolve { reason: } quando a conversa NÃO deve ser cutucada,
  # ou as marcas do plano (clinic_id, leitura_pendente, atendente_encerrou, cold)
  def closure_check(bot, conversation, anchor) # rubocop:disable Metrics/CyclomaticComplexity
    cfg = smart(bot.account)
    # possível bloqueio: a última cutucada DESTE silêncio voltou como "falhou"
    last_status = bot_nudges(conversation).where('created_at >= ?', anchor).reorder(id: :desc).pick(:status)
    return { reason: 'entrega_falhou' } if last_status.to_s == 'failed'

    clinic_id, encerrou = Crm::FollowupClosure.last_clinic(conversation)
    encerrou = encerrou.to_s == 'true'
    cached = Crm::FollowupClosure.current(conversation, clinic_id)
    return { reason: "conversa_#{cached['situacao']}", leitura: cached } if Crm::FollowupClosure::CLOSED.include?(cached&.dig('situacao'))
    # leitura desligada pelo admin: o carimbo de despedida do Atendente ainda vale
    return { reason: 'atendente_encerrou' } if encerrou && !cfg['leitura']

    { clinic_id: clinic_id, atendente_encerrou: encerrou, leitura_pendente: cfg['leitura'] && cached.nil?,
      cold: cfg['lead_frio'] && cold_lead?(conversation) }
  end

  # lead FRIO = nunca escreveu nada (nesta conversa nem em outra do contato):
  # só a 1ª etapa da cadência, e só se ela cai nas primeiras 24h
  def cold_lead?(conversation)
    return false if last_incoming_at(conversation)
    return true if conversation.contact_id.nil?

    !Message.where(account_id: conversation.account_id, message_type: :incoming, private: false)
            .exists?(conversation_id: Conversation.where(contact_id: conversation.contact_id).select(:id))
  end

  def cold_lead_steps(pending, steps)
    first = steps.first
    return [] if first.nil? || Crm::FollowupBot.step_delay_hours(first) > COLD_MAX_HOURS

    pending.select { |d| d[:index].zero? }
  end

  def last_incoming_at(conversation)
    @last_incoming ||= {}
    return @last_incoming[conversation.id] if @last_incoming.key?(conversation.id)

    @last_incoming[conversation.id] = conversation.messages.where(message_type: :incoming, private: false).maximum(:created_at)
  end

  # sábado/domingo (SP) sem fala do paciente no mesmo dia → segunda na
  # abertura do horário de envio. nil = pode sair no próprio momento.
  def weekend_shift(conversation, time) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    return nil unless smart(conversation.account)['fim_de_semana']

    local = time.in_time_zone(TZ)
    return nil unless local.saturday? || local.sunday?
    return nil if last_incoming_at(conversation)&.in_time_zone(TZ)&.to_date == local.to_date

    monday = local.to_date + (local.saturday? ? 2 : 1)
    TZ.local(monday.year, monday.month, monday.day, (@hours || BUSINESS_HOURS).first)
  end

  # LÊ a conversa (IA barata, ou a regra de frases) e guarda a leitura.
  # Devolve nil quando está ABERTA (a cutucada segue) ou { reason:, note: }.
  def read_conversation(conversation, plan) # rubocop:disable Metrics/AbcSize
    @reads = @reads.to_i + 1
    result = Crm::FollowupConversationReader.new(conversation: conversation).call
    situacao = result[:situacao]
    fonte = result[:fonte]
    # carimbo de despedida do Atendente vence um "aberta"
    if situacao == 'aberta' && plan[:atendente_encerrou]
      situacao = 'encerrada'
      fonte = 'atendente'
    end

    data = { 'key' => plan[:clinic_id], 'situacao' => situacao, 'motivo' => result[:motivo], 'fonte' => fonte,
             'at' => Time.current.iso8601 }
    if situacao == 'adiada'
      days = smart(conversation.account).dig('reativacao', 'dias').to_i.clamp(1, 60)
      data['reativar_em'] = days.days.from_now.iso8601
    end
    Crm::FollowupClosure.save!(conversation, data)
    return nil if situacao == 'aberta'

    Crm::FollowupClosure.apply_refusal!(conversation, result[:motivo]) if situacao == 'recusou'
    reason = "conversa_#{situacao}"
    { reason: reason, note: "#{REASON_TEXT[reason]} (#{result[:motivo].to_s.truncate(80)})" }
  end

  # ── 🔁 REATIVAÇÃO de quem ADIOU (decisão B dele, 13/10) ──
  # "ainda não / vou pensar" → UMA mensagem modelo N dias depois (padrão 7),
  # pela caixa da conversa, com o modelo escolhido para aquela caixa. Só em
  # dia útil, no horário de envio. Instagram não tem mensagem modelo: não sai.
  # 🚦 item 345: a reativação entra no MESMO ritmo por número — sai depois das
  # cutucadas da rodada (mensagem modelo não depende da janela de 24h) e,
  # com o número no teto, espera a próxima rodada sem gravar nada.
  def process_reactivations # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
    due = Conversation.where("conversations.additional_attributes -> '#{Crm::FollowupClosure::ATTR}' ->> 'situacao' = 'adiada'")
                      .where("conversations.additional_attributes -> '#{Crm::FollowupClosure::ATTR}' ->> 'reativacao' IS NULL")
                      .where("(conversations.additional_attributes -> '#{Crm::FollowupClosure::ATTR}' ->> 'reativar_em')::timestamptz <= ?",
                             Time.current)
    due.distinct.pluck(:account_id).each do |account_id|
      account = Account.find_by(id: account_id)
      next if account.nil? || !smart(account).dig('reativacao', 'ativa')

      @hours = send_hours(account)
      local = TZ.now
      next unless @hours.cover?(local.hour) && !local.saturday? && !local.sunday?

      tried = 0 # teto REACTIVATIONS_PER_ROUND conta tentativas, como antes; quem espera o ritmo não conta
      due.where(account_id: account_id).includes(:contact, :inbox).order(:id).limit(REACTIVATIONS_PER_ROUND * 5).each do |conversation|
        break if tried >= REACTIVATIONS_PER_ROUND
        next if pace_full?(account, conversation.inbox_id)

        tried += 1
        pace_count!(conversation.inbox_id) if reactivate(conversation)
      rescue StandardError => e
        Rails.logger.error("[CEVICO followup] reativação conversa #{conversation.id}: #{e.message}")
      end
    end
  end

  # true quando a mensagem saiu (conta no ritmo do número)
  def reactivate(conversation)
    data = Crm::FollowupClosure.stored(conversation)
    blocker = reactivation_blocker(conversation, data)
    # trava ANTES de enviar (falha segura: no pior caso perde a reativação, nunca duplica)
    Crm::FollowupClosure.save!(conversation, 'reativacao' => blocker || 'enviada', 'reativacao_at' => Time.current.iso8601)
    return false if blocker

    model = smart(conversation.account).dig('reativacao', 'modelos', conversation.inbox_id.to_s)
    params = render_template_params(model['template_params'], conversation)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
      content: fill_template_text(render_message(model['message'], conversation), params),
      additional_attributes: { cevico_followup_reativacao: true, template_params: params }
    )
    true
  end

  # o texto do modelo vem com {{1}}, {{2}}…: na conversa a equipe vê o texto
  # preenchido (mesma regra do Crm::SendTemplateService#render_content)
  def fill_template_text(text, params)
    values = params.is_a?(Hash) ? (params.dig('processed_params', 'body') || {}) : {}
    text.to_s.gsub(/\{\{\s*(\d+)\s*\}\}/) { values[Regexp.last_match(1)].presence || Regexp.last_match(0) }
  end

  # por que NÃO reativar (nil = pode). Fica gravado em leitura.reativacao.
  def reactivation_blocker(conversation, data) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    return 'perdida' if Time.zone.parse(data['reativar_em'].to_s) < REACTIVATION_STALE_DAYS.days.ago
    return 'conversa_mudou' if Crm::FollowupClosure.last_clinic(conversation)&.first.to_i != data['key'].to_i
    return 'paciente_voltou' if conversation.messages.where(message_type: :incoming).exists?(['created_at > ?', Time.zone.parse(data['at'].to_s)])
    return 'parceiro' if Crm::PartnerGuard.partner_conversation?(conversation) ||
                         Crm::PartnerGuard.partner_inbox_ids(conversation.account).include?(conversation.inbox_id)
    return 'etiqueta' if stop_label?(conversation.account, conversation)
    return 'pausado' if paused_for_patient?(conversation)

    model = smart(conversation.account).dig('reativacao', 'modelos', conversation.inbox_id.to_s)
    return 'sem_modelo' if model.blank? || model['template_params'].blank?
    return 'tem_consulta' if conversation.contact &&
                             Crm::AppointmentRecorder.future_appointment(conversation.account, conversation.contact.phone_number, nil,
                                                                         conversation.contact).present?

    nil
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
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Metrics/MethodLength
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
      # 🧠 fim de semana: só sai no sábado/domingo se o paciente escreveu no
      # mesmo dia — senão a etapa espera a segunda (não é descartada)
      weekend_at = weekend_shift(conversation, send_at)
      # base: âncora/entrada na coluna (identifica a etapa no lembrete do ritmo, item 345)
      { step: step, index: index, from_stage: from_stage, base: base_time, due_at: weekend_at || send_at, spacing: spacing,
        weekend: weekend_at.present?, overdue: (now - (weekend_at || send_at)) / 3600.0 }
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Metrics/MethodLength

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

  # ── 🚦 RITMO DE ENVIO POR NÚMERO (item 345) ──
  # config da conta (Automações → Robôs → "Ritmo de envio"), com padrões
  def pace(account)
    @pace_cache ||= {}
    @pace_cache[account.id] ||= self.class.pace_config(agenda_config(account)['followup_pace'])
  end

  # a caixa (número) já mandou o teto de mensagens na janela do ritmo?
  def pace_full?(account, inbox_id)
    cfg = pace(account)
    return false if cfg['per_window'].zero? # 0 = sem limite

    pace_used(inbox_id, cfg['minutes']) >= cfg['per_window']
  end

  # Fonte da VERDADE = mensagens já enviadas pela caixa nos últimos M min
  # (cutucadas de qualquer robô + reativações), lidas UMA vez por caixa na
  # rodada (sempre antes do 1º envio dela), + o que esta rodada já enviou.
  # Se a rodada demora, a soma só erra para MAIS (as antigas que saíram da
  # janela continuam contadas) — nunca deixa passar do teto. A trava da
  # rodada garante que ninguém mais envia cutucada nesse meio-tempo.
  def pace_used(inbox_id, minutes)
    @pace_base ||= {}
    @pace_base[inbox_id] ||= Message.unscope(:order)
                                    .where(inbox_id: inbox_id, message_type: :outgoing)
                                    .where('messages.created_at >= ?', minutes.minutes.ago)
                                    .where(PACE_MESSAGES_SQL).count
    @pace_base[inbox_id] + pace_sent[inbox_id]
  end

  def pace_sent
    @pace_sent ||= Hash.new(0)
  end

  def pace_count!(inbox_id)
    pace_sent[inbox_id] += 1
  end

  # lembrete "na fila do ritmo" de UMA etapa (robô + conversa + etapa + base
  # da cadência): gravado na 1ª vez que o ritmo segurou a etapa, vale 24h.
  # Fica no Redis, NÃO na conversa — a etapa não é marcada como tratada.
  def pace_hold_key(bot, conversation, due)
    "CEVICO_FOLLOWUP_PACE_HOLD:#{bot.id}:#{conversation.id}:#{due[:from_stage] ? 's' : 'a'}#{due[:index]}:#{due[:base].to_i}"
  end

  def remember_pace_hold(bot, conversation, due)
    Redis::Alfred.set(pace_hold_key(bot, conversation, due), Time.current.to_i, nx: true, ex: PACE_HOLD_TTL.to_i)
  end

  def pace_held?(bot, conversation, due)
    Redis::Alfred.exists?(pace_hold_key(bot, conversation, due))
  end

  # previsão: a próxima cutucada já venceu, mas o número está no teto do ritmo
  def pace_forecast(bot, conversation, timeline, text)
    return text unless pace_full?(bot.account, conversation.inbox_id)

    cfg = pace(bot.account)
    timeline.each { |t| t[:note] = 'na fila do ritmo de envio' if t[:status] == 'proxima' }
    qty = cfg['per_window'] == 1 ? '1 mensagem' : "#{cfg['per_window']} mensagens"
    "#{text} · na fila do ritmo de envio (até #{qty} a cada #{cfg['minutes']} min por número)"
  end

  # etiquetas de encerramento configuradas pelo admin (além das fixas)
  def stop_labels(account)
    @stop_labels_cache ||= {}
    @stop_labels_cache[account.id] ||= Array(agenda_config(account)['followup_stop_labels'])
                                       .map { |l| l.to_s.strip.downcase }.reject(&:blank?)
  end

  def signal_stop_labels(account)
    @signal_stop_labels_cache ||= {}
    @signal_stop_labels_cache[account.id] ||= Crm::StopSignals.robot_stop_labels(account)
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
    # 🚦 Saúde do WhatsApp (16/10): sinais de quem não quer receber com a chavinha "robôs param" ligada
    return true if labels.intersect?(signal_stop_labels(account))

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
  # Nota interna (outgoing + private) NÃO conta: o paciente não a viu — se a
  # última coisa visível é a pergunta dele, a vez é do atendimento (varredura 03/10).
  def silence_anchor(conversation)
    msgs = conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
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
    same_anchor = mine['anchor'] == anchor.iso8601

    # 🔴 o .dup é OBRIGATÓRIO — sem ele, o << do mark_steps mutava o MESMO
    # array que vive no additional_attributes carregado, o with_lock do
    # merge atômico recusava o registro "sujo" e a rodada caía em erro TODA
    # VEZ após a 1ª cutucada (só o primeiro follow-up saía — bug de produção
    # 03/08; mesma lição do item 98: deep_dup antes do lock)
    {
      'sent' => same_anchor ? Array(mine['sent']).dup : [],
      'stage_sent' => mine['stage_key'] == stage_key ? Array(mine['stage_sent']).dup : [],
      'stage_key' => stage_key,
      'ai_tries' => same_anchor ? (mine['ai_tries'] || {}).dup : {} # item 315
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
        'stage_key' => state['stage_key'], 'stage_sent' => state['stage_sent'],
        'ai_tries' => state['ai_tries'].presence
      }.compact
      attrs.merge('cevico_followup' => stored)
    end
  end

  def send_nudge(bot, conversation, chosen, content)
    step = chosen[:step]
    # cada cutucada carrega o robô E o nº da etapa (linha do tempo da previsão)
    attrs = { cevico_followup_bot_id: bot.id, cevico_followup_step: chosen[:index] }
    # 🧠 medição por coluna do CRM (Resultado do follow-up): a coluna NA HORA do envio
    stage_id = conversation.contact_id && Crm::Contact.where(contact_id: conversation.contact_id).order(updated_at: :desc).pick(:stage_id)
    attrs[:cevico_followup_stage_id] = stage_id if stage_id
    attrs[:cevico_followup_ai] = true if Crm::FollowupBot.ai_step?(step) # item 315: escrita pela IA
    # etapa de MENSAGEM MODELO: envia o template oficial (funciona fora da
    # janela de 24h do WhatsApp — ideal para cadências em dias)
    attrs[:template_params] = render_template_params(step['template_params'], conversation) if step['template_params'].present?

    conversation.messages.create!(
      account_id: bot.account_id,
      inbox_id: conversation.inbox_id, # robô por coluna envia na caixa da própria conversa
      message_type: :outgoing,
      content: content,
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
                    note: timeline_wait_note(pending[i])).compact
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
      # 🧠 leitura da conversa: diz também o porquê (motivo da IA ou da regra)
      why = plan[:leitura] && plan[:leitura]['motivo'].present? ? " (#{plan[:leitura]['motivo']})" : ''
      ['parado', "#{REASON_TEXT.fetch(reason, reason.to_s)}#{why}#{tail}"]
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def timeline_wait_note(pending)
    return 'fim de semana: espera a segunda' if pending[:weekend]

    pending[:spacing] ? 'espaçamento da cadência' : nil
  end

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
    Crm::FollowupBot.ai_step?(step) ? "cutucada de #{value}#{unit} (IA)" : "cutucada de #{value}#{unit}"
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
