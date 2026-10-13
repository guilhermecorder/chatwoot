# Radar de Oportunidades: audita as colunas configuradas e encontra cards
# "quentes" parados sem atendimento (ex.: paciente pronto para agendar há
# mais de 10 minutos na coluna Envio de Orçamento). Para cada oportunidade
# cria um AVISO no Meu Painel com nome, motivo e o que a atendente deve
# fazer — para nunca mais perder agendamento por falta de atendimento.
#
# Config em "vigias" (watchers): cada vigia = coluna + painel do atendente
# que recebe o aviso (nil = todos) + janela de tempo própria (6/12/24/48h).
#
# Dois modos:
# - PERENE: roda pelo cron (a cada 10 min) via Crm::OpportunityRadarJob,
#   usando as vigias salvas na config.
# - PONTUAL: varredura única pedida na tela (overrides com coluna/etiqueta/
#   período/atendente) — roda uma vez e NÃO fica ativa.
class Crm::OpportunityRadarService
  include Crm::AiAgentConfig

  AGENT_KEY = 'opportunity'.freeze
  DEFAULT_WAIT_MINUTES = 10
  DEFAULT_LOOKBACK_HOURS = 24 # só olha movimento NOVO (não o estoque da coluna)
  MAX_ANALYSES_PER_RUN = 15   # teto de chamadas de IA por rodada automática
  MAX_ANALYSES_MANUAL = 40    # teto para varredura manual
  RECHECK_AFTER = 6.hours     # não reanalisa a mesma conversa antes disso
  ALERT_TTL = 24.hours
  HISTORY_LIMIT = 500         # detecções guardadas p/ o Dashboard
  MAX_MESSAGES = 40

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      oportunidade: {
        type: 'boolean',
        description: 'true se o paciente está QUENTE: pronto/querendo agendar consulta ou avançar agora'
      },
      motivo: { type: 'string', description: 'Por que este card é uma oportunidade, em 1 frase concreta e direta (cite o que o paciente disse)' },
      acao: {
        type: 'string',
        description: 'Orientação para a atendente em tom PROFESSORAL e calmo (1-2 frases): o que fazer e por quê, ' \
                     'como um bom professor orienta — sem tom de alarme, sem "imediatamente/agora/urgente"'
      }
    },
    required: %w[oportunidade motivo acao],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o Radar de Oportunidades da CEVICO (clínica oftalmológica). Vai
    receber a conversa de um paciente que está numa coluna do CRM aguardando
    resposta da clínica há um tempo.

    Decida se é uma OPORTUNIDADE QUENTE: paciente demonstrando que quer
    agendar consulta, aceitar orçamento ou avançar AGORA (ex.: perguntou
    horários, disse "pode marcar", aceitou o valor, pediu disponibilidade).

    - oportunidade=true SÓ quando há sinal claro de intenção de avançar.
    - Dúvida genérica, pedido de informação fria ou conversa morna → false.
    - motivo: DIRETO ao ponto — cite concretamente o que o paciente disse/pediu.
    - acao: tom PROFESSORAL e tranquilo, como um bom professor orientando a
      atendente: o que fazer e por quê, sem alarme e sem palavras de urgência
      ("imediatamente", "agora", "urgente"). Ex.: "Vale oferecer dois horários
      da semana para o retorno em Mogi — data e hora definidas costumam fechar
      o agendamento."

    ATENÇÃO à etapa da jornada (vem no cabeçalho): quando a coluna for de
    PÓS-CONSULTA (compareceu à consulta, indicação de cirurgia, não fechou
    ainda, pós-operatório), o paciente costuma estar ANSIOSO — sinais de
    oportunidade incluem dúvidas sobre a cirurgia, medo, preço, recuperação
    ou silêncio depois da indicação. Nesses casos a acao deve orientar
    acolhimento: responder as dúvidas com calma, reforçar segurança e
    próximos passos, sem pressão comercial.
    Escreva em português do Brasil.
  PROMPT

  def initialize(account:)
    @account = account
  end

  # overrides (radar pontual): stage_ids, label, since_hours, user_id
  def call(overrides = {})
    @overrides = overrides.symbolize_keys
    return { skipped: 'pausado' } if agent_paused?
    return { skipped: 'sem chave de API' } if api_key.blank?
    return { skipped: 'nenhuma coluna configurada' } if effective_watchers.empty?

    state = radar_state
    # 🔒 (#102) foto do estado no COMEÇO da rodada: no fim, save_state compara
    # com o estado fresco para não apagar o que entrou/saiu enquanto a IA rodava
    @state_at_start = state.deep_dup
    kept_alerts = still_valid_alerts(state['alerts'])
    checked = prune_checked(state['checked'])
    history = Array(state['history'])

    analyzed = 0
    total_candidates = 0
    new_alerts = []
    max = manual? ? MAX_ANALYSES_MANUAL : MAX_ANALYSES_PER_RUN

    effective_watchers.each do |watcher|
      candidates = candidate_conversations(watcher).to_a
      total_candidates += candidates.size

      candidates.each do |conversation|
        break if analyzed >= max
        next if kept_alerts.any? { |a| a['conversation_id'] == conversation.display_id }
        next if new_alerts.any? { |a| a['conversation_id'] == conversation.display_id }
        next if !manual? && checked[conversation.display_id.to_s].present?

        analyzed += 1
        checked[conversation.display_id.to_s] = Time.current.iso8601

        verdict = analyze(conversation, stage_of(conversation)&.name)
        next unless verdict && verdict['oportunidade']

        new_alerts << build_alert(conversation, verdict, watcher)
        # histórico com destino e coluna — alimenta a responsividade do
        # Radar no Dashboard dos Agentes (quem respondeu e em quanto tempo)
        history << {
          'conversation_id' => conversation.display_id,
          'detected_at' => Time.current.iso8601,
          'user_id' => watcher[:user_id],
          'stage_name' => stage_of(conversation)&.name
        }.compact
      end
    end

    last_run = {
      'at' => Time.current.iso8601,
      'mode' => manual? ? 'manual' : 'auto',
      'candidates' => total_candidates,
      'analyzed' => analyzed,
      'new_alerts' => new_alerts.size
    }
    # o que ficou válido e o que foi achado NESTA rodada vão separados: assim o
    # aviso vencido que foi redetectado entra na versão nova (não na velha)
    save_state(kept_alerts, new_alerts, checked, history.last(HISTORY_LIMIT), last_run)
    { alerts: kept_alerts.size + new_alerts.size, new: new_alerts.size, analyzed: analyzed, candidates: total_candidates }
  end

  private

  def manual?
    @overrides.present? && @overrides.values.any?(&:present?)
  end

  # vigias salvas na config: cada uma com coluna + atendente + janela.
  # Compat: config antiga (stage_ids + lookback_hours únicos) vira vigia
  # sem direcionamento até ser salva de novo pela tela.
  def watchers
    list = Array(agent_config['watchers']).filter_map do |w|
      stage_id = w['stage_id'].to_i
      next if stage_id.zero?

      { stage_id: stage_id, user_id: w['user_id'].presence&.to_i, lookback_hours: normalize_hours(w['lookback_hours']) }
    end
    return list if list.any?

    Array(agent_config['stage_ids']).map(&:to_i).reject(&:zero?).map do |stage_id|
      { stage_id: stage_id, user_id: nil, lookback_hours: normalize_hours(agent_config['lookback_hours']) }
    end
  end

  # radar pontual: monta vigias descartáveis a partir dos overrides
  # (coluna/período/atendente escolhidos na janela). Sem coluna escolhida,
  # varre as colunas das vigias perenes.
  def effective_watchers
    return watchers unless manual?

    stage_ids = Array(@overrides[:stage_ids]).map(&:to_i).reject(&:zero?)
    stage_ids = watchers.map { |w| w[:stage_id] }.uniq if stage_ids.empty?
    hours = normalize_hours(@overrides[:since_hours])
    user_id = @overrides[:user_id].presence&.to_i

    stage_ids.map { |id| { stage_id: id, user_id: user_id, lookback_hours: hours } }
  end

  def watched_stage_ids
    effective_watchers.map { |w| w[:stage_id] }.uniq
  end

  def normalize_hours(value)
    h = value.to_i
    h.positive? ? h : DEFAULT_LOOKBACK_HOURS
  end

  def wait_minutes
    m = agent_config['wait_minutes'].to_i
    m.positive? ? m : DEFAULT_WAIT_MINUTES
  end

  # conversas abertas de contatos na coluna da vigia, com o paciente
  # esperando resposta há mais de N minutos — e só o movimento novo
  # (dentro da janela de tempo da vigia)
  def candidate_conversations(watcher)
    contacts = Crm::Contact.joins(:pipeline)
                           .where(crm_pipelines: { account_id: @account.id })
                           .where(stage_id: watcher[:stage_id])

    scope = @account.conversations
                    .open
                    .where(contact_id: contacts.select(:contact_id))
                    .where.not(waiting_since: nil)
                    .where(waiting_since: watcher[:lookback_hours].hours.ago..wait_minutes.minutes.ago)

    # varredura por etiqueta (do contato)
    if (label = @overrides&.dig(:label)).present?
      tagged_ids = ActsAsTaggableOn::Tagging
                   .joins(:tag)
                   .where(taggable_type: 'Contact', context: 'labels')
                   .where(tags: { name: label })
                   .select(:taggable_id)
      scope = scope.where(contact_id: tagged_ids)
    end

    scope.order(waiting_since: :asc).limit(80)
  end

  def analyze(conversation, stage_name = nil)
    transcript = build_transcript(conversation, stage_name)
    return nil if transcript.blank?

    message = client.messages.create(
      model: model,
      max_tokens: 512,
      system_: cached_system,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: transcript }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    text.present? ? JSON.parse(text) : nil
  rescue StandardError => e
    Rails.logger.error "[Crm::OpportunityRadar] #{e.class}: #{e.message}"
    nil
  end

  def build_alert(conversation, verdict, watcher)
    contact = conversation.contact
    stage = stage_of(conversation)
    {
      'conversation_id' => conversation.display_id,
      'contact_id' => conversation.contact_id,
      'contact_name' => contact&.name.presence || 'Paciente',
      'phone' => contact&.phone_number,
      'stage_name' => stage&.name,
      'assignee_name' => conversation.assignee&.available_name,
      'waiting_since' => conversation.waiting_since&.iso8601,
      'motivo' => verdict['motivo'],
      'acao' => verdict['acao'],
      # painel de destino do aviso (nil = aparece para todos)
      'user_id' => watcher[:user_id],
      'user_name' => target_user_name(watcher[:user_id]),
      'created_at' => Time.current.iso8601
    }
  end

  def target_user_name(user_id)
    return nil if user_id.blank?

    @target_user_names ||= {}
    @target_user_names[user_id] ||= @account.users.find_by(id: user_id)&.available_name
  end

  def stage_of(conversation)
    crm = Crm::Contact.joins(:pipeline)
                      .where(crm_pipelines: { account_id: @account.id })
                      .find_by(contact_id: conversation.contact_id, stage_id: watched_stage_ids)
    crm&.stage
  end

  # aviso some quando a conversa foi atendida (waiting_since limpo/fechada)
  # ou quando envelhece demais
  def still_valid_alerts(alerts)
    Array(alerts).select do |a|
      created = Time.zone.parse(a['created_at'].to_s) rescue nil
      next false if created.nil? || created < ALERT_TTL.ago
      # ligação perdida (167) / "não vou" da jornada (168): valem até alguém retornar
      next Crm::RadarExtraAlerts.still_open?(@account, a) if Crm::RadarExtraAlerts.extra?(a)

      conv = @account.conversations.find_by(display_id: a['conversation_id'])
      conv&.open? && conv.waiting_since.present?
    end
  end

  def prune_checked(checked)
    Hash(checked).select do |_id, ts|
      t = Time.zone.parse(ts.to_s) rescue nil
      t.present? && t > RECHECK_AFTER.ago
    end
  end

  def radar_state
    (ai_config['opportunity_state'] || {}).tap do |s|
      s['alerts'] ||= []
      s['checked'] ||= {}
      s['history'] ||= []
    end
  end

  # 🔒 Rodada 4 da auditoria (#102): grava sob a trava da linha (Cevico::
  # SettingMerge) relendo o estado FRESCO. A rodada demora minutos (chamadas
  # de IA) e, nesse meio-tempo, outros escritores mexem na MESMA lista de
  # avisos: Crm::AgentAlert (cancelou/remarcou/não confirmou/pós-op), ligação
  # perdida, "não vou" da jornada e o "Atender agora" do carrossel. Antes, o
  # Radar gravava a foto do começo e apagava tudo isso. Regra do acerto:
  # - aviso que ENTROU durante a rodada (qualquer tipo) fica;
  # - aviso ATENDIDO durante a rodada (saiu da lista) não volta;
  # - aviso que este Radar julgou vencido sai; o que ele achou de novo entra
  #   (aviso vencido REDETECTADO = entra a versão nova, não a velha);
  # - as outras chaves do estado (manual_log, attended_log) ficam como estão.
  # kept_alerts = o que já estava e continua válido; new_alerts = o que o
  # Radar achou NESTA rodada (nunca deduzido por identidade contra a foto do
  # começo — senão o redetectado com o mesmo id ficava com a versão velha).
  def save_state(kept_alerts, new_alerts, checked, history, last_run)
    kept_ids = kept_alerts.map { |a| alert_id(a) }
    new_ids = new_alerts.map { |a| alert_id(a) }
    new_history = history - Array(@state_at_start.to_h['history'])

    Cevico::SettingMerge.merge_key!(@account, :ai_config, 'opportunity_state') do |state|
      survivors = fresh_survivors(state['alerts'], kept_ids, new_ids)
      state.merge(
        'alerts' => (survivors + new_alerts).last(30),
        'checked' => prune_checked(Hash(state['checked']).merge(checked)),
        'history' => (Array(state['history']) + new_history).last(HISTORY_LIMIT),
        'last_run' => last_run,
        'last_run_at' => last_run['at']
      )
    end
    @ai_config = nil # limpa memo
  end

  # avisos do estado FRESCO que ficam:
  # - redetectado agora (id em new_ids): sai, a versão nova entra depois;
  # - não estava na foto do começo: entrou durante a rodada → fica;
  # - estava na foto, mas o fresco tem created_at mais novo: foi REGRAVADO
  #   durante a rodada (ex.: AgentAlert da mesma tarefa depois do TTL) → fica;
  # - estava na foto e este Radar ainda considera válido (kept) → fica;
  # - o resto (vencido/atendido segundo este Radar) sai.
  def fresh_survivors(fresh, kept_ids, new_ids)
    start_at = Array(@state_at_start.to_h['alerts']).to_h { |a| [alert_id(a), alert_time(a)] }
    Array(fresh).select do |a|
      id = alert_id(a)
      next false if new_ids.include?(id)
      next true unless start_at.key?(id)
      next true if newer?(alert_time(a), start_at[id])

      kept_ids.include?(id)
    end
  end

  def alert_time(alert)
    Time.zone.parse(alert['created_at'].to_s)
  rescue ArgumentError
    nil
  end

  def newer?(time, reference)
    time.present? && (reference.nil? || time > reference)
  end

  # identidade de um aviso: os extras (ligação, jornada, agente) se repetem
  # pelo id da ligação/envio/tarefa; os do próprio Radar, pela conversa
  def alert_id(alert)
    extra = alert['call_id'] || alert['send_id'] || alert['task_id']
    [alert['kind'].to_s, (extra || alert['conversation_id']).to_s]
  end

  def build_transcript(conversation, stage_name = nil)
    # reorder: o default_scope do Message (created_at ASC) vence um .order
    # comum, então pegava as N mensagens mais ANTIGAS e a IA nunca via as novas
    messages = conversation.messages
                           .where(message_type: [:incoming, :outgoing])
                           .where(private: false)
                           .where.not(content: [nil, ''])
                           .reorder(created_at: :desc)
                           .limit(MAX_MESSAGES)
                           .reverse

    return nil if messages.empty?

    waiting_min = ((Time.current - conversation.waiting_since) / 60).round
    lines = messages.map do |m|
      author = m.incoming? ? 'PACIENTE' : 'CLÍNICA'
      "[#{m.created_at.strftime('%d/%m %H:%M')}] #{author}: #{m.content.to_s.strip.truncate(500)}"
    end

    stage_line = stage_name.present? ? "Etapa da jornada (coluna do CRM): #{stage_name}.\n" : ''
    "Paciente #{conversation.contact&.name || 'sem nome'} aguarda resposta há #{waiting_min} minutos.\n" \
      "#{stage_line}Conversa:\n\n#{lines.join("\n")}"
  end
end
