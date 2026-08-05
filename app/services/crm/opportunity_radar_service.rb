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
    save_state(kept_alerts + new_alerts, checked, history.last(HISTORY_LIMIT), last_run)
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
      system_: system_prompt,
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
      'contact_name' => contact&.name.presence || Segmento.termo_cap(:cliente),
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

  def save_state(alerts, checked, history, last_run)
    settings = CrmSetting.find_or_create_by!(account: @account)
    cfg = settings.ai_config || {}
    cfg['opportunity_state'] = {
      'alerts' => alerts.last(30),
      'checked' => checked,
      'history' => history,
      'last_run' => last_run,
      'last_run_at' => last_run['at']
    }
    settings.update!(ai_config: cfg)
    @ai_config = nil # limpa memo
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
      author = m.incoming? ? Segmento.termo(:cliente).upcase : Segmento.termo(:empresa).upcase
      "[#{m.created_at.strftime('%d/%m %H:%M')}] #{author}: #{m.content.to_s.strip.truncate(500)}"
    end

    stage_line = stage_name.present? ? "Etapa da jornada (coluna do CRM): #{stage_name}.\n" : ''
    "#{Segmento.termo_cap(:cliente)} #{conversation.contact&.name || 'sem nome'} aguarda resposta há #{waiting_min} minutos.\n" \
      "#{stage_line}Conversa:\n\n#{lines.join("\n")}"
  end
end
