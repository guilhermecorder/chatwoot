# 🎓 MOTOR DE EDUCAÇÃO do atendimento (item 389, pedido dele 05/11): todo dia
# de manhã lê as conversas de ONTEM, separa as que viraram consulta agendada
# das que não viraram e pede à IA o que diferencia uma da outra. Sai no máximo
# MAX_SUGGESTIONS aprendizados novos, cada um com a conversa de exemplo, que
# viram ORIENTAÇÕES pendentes (Crm::AgentGuidance, source 'motor').
#
# Nada muda sozinho: o admin aprova com um toque. Aprovar tira a FOTO dos
# aprendizados atuais (Crm::ScriptVersion kind 'motor') e acrescenta a linha.
# Os aprendizados aprovados NÃO entram no Roteiro de todos: valem só nas
# CAIXAS PILOTO (ai_config['motor']['pilot_inbox_ids']), no Atendente de
# Agendamento, como um bloco no fim da etapa. Desligar o motor tira o bloco
# na hora (reversão sem deploy).
#
# PLACAR: a cada dia lido guarda, por caixa, quantas conversas novas houve e
# quantas agendaram. A tela compara a caixa piloto com a de comparação, antes
# e depois de cada aprendizado.
#
# Tudo em ai_config['motor'] (sem migration):
#   enabled, pilot_inbox_ids, control_inbox_ids, rules (texto, 1 linha por
#   aprendizado), rules_updated_at, state { days, why, last_run_at }
class Crm::EducationEngine # rubocop:disable Metrics/ClassLength
  include Crm::AiAgentConfig

  AGENT_KEY = 'motor'.freeze
  CONFIG_KEY = 'motor'.freeze
  TARGET_AGENT = 'atendente_agendamento'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  MAX_PER_GROUP = 15      # conversas que agendaram × que não agendaram, por dia
  MAX_MESSAGES = 30       # últimas N mensagens de cada conversa
  MAX_SUGGESTIONS = 5
  CANDIDATE_CAP = 400     # conversas olhadas por dia (placar)
  KEEP_DAYS = 120
  MAX_RULES_CHARS = 6000  # teto do bloco de aprendizados (não incha o prompt)

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      resumo: { type: 'string', description: 'Leitura do dia em 2-3 frases simples: o que separou quem agendou de quem não agendou' },
      padroes_que_agendaram: { type: 'array', items: { type: 'string' } },
      padroes_que_perderam: { type: 'array', items: { type: 'string' } },
      aprendizados: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            regra: { type: 'string', description: 'O aprendizado como regra curta e acionável para o atendente (1-2 frases)' },
            por_que: { type: 'string', description: 'Por que esta regra deve aumentar o agendamento, citando o que se viu nas conversas' },
            conversa_id: { type: 'integer', description: 'id da conversa de exemplo' },
            paciente_disse: { type: 'string' },
            atendente_disse: { type: 'string' },
            deveria_dizer: { type: 'string', description: 'A resposta ideal, pronta, no tom CEVICO' },
            confianca: { type: 'string', enum: %w[alta media] }
          },
          required: %w[regra por_que conversa_id paciente_disse atendente_disse deveria_dizer confianca],
          additionalProperties: false
        }
      }
    },
    required: %w[resumo padroes_que_agendaram padroes_que_perderam aprendizados],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o MOTOR DE EDUCAÇÃO do atendimento da CEVICO (clínica de
    oftalmologia focada em cirurgia refrativa e de catarata, em São Paulo).
    Todo dia você recebe o ROTEIRO que o atendente segue hoje e as conversas
    REAIS de ontem, em dois grupos: as que viraram consulta AGENDADA e as que
    NÃO viraram. Sua missão é ensinar o atendente a agendar mais, sem perder a
    segurança nem o jeito CEVICO.

    Como trabalhar:
    - Compare os dois grupos: o que o atendimento fez nas que agendaram e
      deixou de fazer nas que não agendaram (pergunta ignorada, resposta
      longa demais, valor sem contexto, falta de convite, demora, tom frio,
      objeção mal respondida, horário não oferecido...).
    - Proponha no máximo #{MAX_SUGGESTIONS} aprendizados NOVOS. Cada um é uma regra
      curta e acionável, com UMA conversa de exemplo real (o id que veio no
      texto), o que o paciente disse, o que o atendente disse e o que deveria
      ter dito.
    - Prefira o que apareceu em mais de uma conversa (confianca "alta").
      Um caso isolado só entra se o erro for claro (confianca "media").
    - Não repita o que o roteiro ou os aprendizados atuais já dizem. Se o
      atendente DESCUMPRIU uma regra que já existe, o aprendizado reforça a
      regra com o exemplo concreto.
    - Se não houver nada novo e útil, devolva a lista vazia. Zero é melhor
      que um aprendizado fraco.

    Limites que você nunca cruza:
    - Não muda valores, formas de pagamento, unidades, horários, médicos nem
      nenhum DADO OFICIAL; não sugere desconto nem condição especial.
    - Não promete resultado de cirurgia. A cirurgia só é indicada quando é
      segura e eficaz para a pessoa; isso quem diz é a avaliação.
    - Respeita o PROCESSO DE VENDAS do roteiro (recepção, sondagem,
      autoridade, promessa do valor, orçamento, agendamento). Pode deixá-lo
      mais flexível (pular etapa já respondida, responder a dúvida e voltar
      ao passo), nunca trocá-lo por outro.
    - Nunca cita nome de médico que o roteiro não cita.
    - Português do Brasil, simples. As regras são lidas pela IA e pelo dono
      da clínica, então nada de jargão.
  PROMPT

  def initialize(account:)
    @account = account
  end

  attr_reader :account

  # ── leitura da configuração (usada também pelo atendente) ─────────────

  def self.settings(account)
    (CrmSetting.find_by(account: account)&.ai_config || {})[CONFIG_KEY] || {}
  end

  def self.enabled?(account, cfg = settings(account))
    cfg['enabled'] == true
  end

  def self.pilot_inbox_ids(cfg)
    Array(cfg['pilot_inbox_ids']).map(&:to_i).select(&:positive?)
  end

  def self.control_inbox_ids(cfg)
    Array(cfg['control_inbox_ids']).map(&:to_i).select(&:positive?)
  end

  def self.rules(account)
    settings(account)['rules'].to_s.strip
  end

  # o bloco que entra no fim da etapa do Atendente de Agendamento, SÓ nas
  # caixas piloto e com o motor ligado (nil nos demais casos)
  def self.prompt_block(conversation, agent_key)
    return nil unless agent_key.to_s == TARGET_AGENT && conversation&.inbox_id

    cfg = settings(conversation.account)
    return nil unless enabled?(conversation.account, cfg) && pilot_inbox_ids(cfg).include?(conversation.inbox_id)

    text = cfg['rules'].to_s.strip
    return nil if text.blank?

    "\n\n== APRENDIZADOS DO MOTOR DE EDUCAÇÃO (aprovados pela clínica, valem nesta caixa) ==\n#{text}\n" \
      'Se algum aprendizado contrariar os DADOS OFICIAIS ou as regras de segurança do roteiro, valem os DADOS OFICIAIS.'
  end

  # ── escrita (sob trava, relendo a config fresca) ──────────────────────

  def self.write!(account)
    saved = Cevico::SettingMerge.merge!(account, :ai_config) do |ai|
      ai[CONFIG_KEY] = yield((ai[CONFIG_KEY] || {}).deep_dup)
      ai
    end
    saved[CONFIG_KEY] || {}
  end

  def self.update_settings!(account, enabled: nil, pilot_inbox_ids: nil, control_inbox_ids: nil)
    write!(account) do |cfg|
      cfg['enabled'] = enabled == true unless enabled.nil?
      cfg['pilot_inbox_ids'] = clean_ids(pilot_inbox_ids) unless pilot_inbox_ids.nil?
      cfg['control_inbox_ids'] = clean_ids(control_inbox_ids) - Array(cfg['pilot_inbox_ids']) unless control_inbox_ids.nil?
      cfg
    end
  end

  def self.clean_ids(ids)
    Array(ids).map(&:to_i).select(&:positive?).uniq.first(10)
  end

  # grava o texto inteiro dos aprendizados (editar na tela / voltar versão)
  def self.write_rules!(account, text)
    clean = text.to_s.strip.first(MAX_RULES_CHARS)
    write!(account) { |cfg| cfg.merge('rules' => clean, 'rules_updated_at' => Time.current.iso8601) }['rules'].to_s
  end

  # orientação aprovada: uma linha a mais no fim (relida dentro da trava)
  def self.append_rule!(account, line)
    write!(account) do |cfg|
      text = [cfg['rules'].to_s.strip.presence, line.to_s.strip].compact.join("\n")
      cfg.merge('rules' => text.first(MAX_RULES_CHARS), 'rules_updated_at' => Time.current.iso8601)
    end['rules'].to_s
  end

  # ── a leitura diária ──────────────────────────────────────────────────

  def call(day: TZ.yesterday, force: false) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    cfg = self.class.settings(account)
    return { skipped: 'desligado' } unless self.class.enabled?(account, cfg)
    return { skipped: 'sem chave de IA' } if api_key.blank?
    return { skipped: 'já leu este dia' } if !force && cfg.dig('state', 'days', day.iso8601, 'status') == 'ok'

    convs = day_conversations(day)
    booked_ids = booked_contact_ids(convs, day)
    booked, lost = convs.partition { |c| booked_ids.include?(c.contact_id) }
    score = scoreboard(convs, booked_ids)
    return finish_day(day, score, status: 'sem conversas') if convs.empty?

    verdict = ask(day, pick(booked), pick(lost))
    return finish_day(day, score, status: 'erro', error: verdict[:error]) if verdict[:error]

    created = save_suggestions(verdict)
    finish_day(day, score, status: 'ok', verdict: verdict, created: created,
                           read: { booked: [booked.size, MAX_PER_GROUP].min, lost: [lost.size, MAX_PER_GROUP].min })
  end

  private

  # o motor tem o próprio interruptor (ai_config['motor']['enabled']); modelo
  # e esforço seguem o padrão do agente 'motor' / global
  def agent_paused?
    !self.class.enabled?(account)
  end

  def default_system_prompt
    SYSTEM_PROMPT
  end

  def day_range(day)
    start = TZ.parse(day.iso8601).beginning_of_day
    start..start.end_of_day
  end

  # conversas em que o PACIENTE escreveu no dia e alguém respondeu; quem já
  # tinha consulta marcada antes do dia fica de fora (não é lead, é paciente
  # agendado tirando dúvida — distorce o placar)
  def day_conversations(day) # rubocop:disable Metrics/AbcSize
    range = day_range(day)
    ids = account.conversations.joins(:messages)
                 .where(messages: { created_at: range, message_type: %i[incoming outgoing], private: false })
                 .group('conversations.id')
                 .having("COUNT(*) FILTER (WHERE messages.message_type = #{Message.message_types[:incoming]}) >= 1")
                 .having("COUNT(*) FILTER (WHERE messages.message_type = #{Message.message_types[:outgoing]}) >= 1")
                 .order(Arel.sql('COUNT(messages.id) DESC'))
                 .limit(CANDIDATE_CAP)
                 .pluck('conversations.id')
    convs = account.conversations.where(id: ids).includes(:contact).to_a
    already = already_scheduled_contact_ids(convs.map(&:contact_id), range.first)
    convs.reject { |c| c.contact_id.nil? || already.include?(c.contact_id) }
  end

  def already_scheduled_contact_ids(contact_ids, day_start)
    Task.where(account_id: account.id, contact_id: contact_ids, task_type: 'consulta')
        .where('created_at < ? AND due_at >= ?', day_start, day_start)
        .distinct.pluck(:contact_id).to_set
  end

  # agendou = nasceu uma consulta para o contato do início do dia até agora
  def booked_contact_ids(convs, day)
    Task.where(account_id: account.id, contact_id: convs.map(&:contact_id), task_type: 'consulta')
        .where(created_at: day_range(day).first..Time.current)
        .distinct.pluck(:contact_id).to_set
  end

  # por caixa: conversas e quantas agendaram
  def scoreboard(convs, booked_ids)
    convs.group_by(&:inbox_id).transform_keys(&:to_s).transform_values do |list|
      { 'n' => list.size, 'booked' => list.count { |c| booked_ids.include?(c.contact_id) } }
    end
  end

  # as mais conversadas primeiro (mais ricas de aprendizado)
  def pick(list)
    list.first(MAX_PER_GROUP)
  end

  def ask(day, booked, lost)
    message = client.messages.create(
      model: model, max_tokens: 16_000, system_: cached_system(SYSTEM_PROMPT),
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: user_content(day, booked, lost) }]
    )
    record_usage(message)
    parsed = parse_structured_response(message)
    return { error: parsed[:error] } if parsed.is_a?(Hash) && parsed[:error]

    parsed.is_a?(Hash) ? parsed : { error: 'Resposta fora do formato.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::EducationEngine] conta=#{account.id} #{e.class}: #{e.message}"
    { error: e.message }
  end

  def user_content(day, booked, lost)
    current = self.class.rules(account)
    <<~TEXT
      == ROTEIRO QUE O ATENDENTE SEGUE HOJE ==
      #{Crm::CevicoScript.text(account)}

      == ETAPA DO ATENDENTE DE AGENDAMENTO ==
      #{Crm::CevicoScript.stage_prompt(account, TARGET_AGENT)}

      == APRENDIZADOS JÁ APROVADOS (não repita) ==
      #{current.presence || '(nenhum ainda)'}

      == CONVERSAS DE #{day.strftime('%d/%m/%Y')} QUE VIRARAM CONSULTA AGENDADA (#{booked.size}) ==
      #{booked.map { |c| transcript(c) }.join("\n\n---\n\n").presence || '(nenhuma)'}

      == CONVERSAS DE #{day.strftime('%d/%m/%Y')} QUE NÃO VIRARAM CONSULTA (#{lost.size}) ==
      #{lost.map { |c| transcript(c) }.join("\n\n---\n\n").presence || '(nenhuma)'}
    TEXT
  end

  def transcript(conv)
    msgs = conv.messages.where(message_type: %i[incoming outgoing], private: false)
               .reorder(created_at: :desc).limit(MAX_MESSAGES).to_a.reverse
    lines = msgs.map { |m| "#{speaker(m)}: #{m.content.to_s.gsub(/\s+/, ' ').truncate(300)}" }
    "CONVERSA id=#{conv.display_id} (caixa #{conv.inbox_id})\n#{lines.join("\n")}"
  end

  def speaker(message)
    return 'PACIENTE' if message.incoming?
    return 'ATENDENTE (IA)' if (message.additional_attributes || {})['cevico_ia_agent'].present?

    'ATENDENTE (equipe)'
  end

  def save_suggestions(verdict) # rubocop:disable Metrics/AbcSize
    Array(verdict['aprendizados']).first(MAX_SUGGESTIONS).filter_map do |row|
      rule = row['regra'].to_s.squish
      next if rule.blank? || duplicate_rule?(rule)

      guidance = Crm::AgentGuidance.create!(
        account: account, agent_key: TARGET_AGENT, source: 'motor', target_section: 'motor',
        conversation_id: row['conversa_id'].to_i.positive? ? row['conversa_id'].to_i : nil,
        patient_excerpt: row['paciente_disse'].to_s.strip.first(1000),
        agent_text: row['atendente_disse'].to_s.strip.first(2000),
        ideal_reply: row['deveria_dizer'].to_s.strip.first(2000), rule: rule.first(600)
      )
      { 'id' => guidance.id, 'why' => row['por_que'].to_s.squish.first(600), 'confidence' => row['confianca'] }
    end
  end

  # a mesma regra pendente (ou já aprovada) não volta todo dia
  def duplicate_rule?(rule)
    key = rule.downcase.gsub(/[^a-z0-9à-ú]/, '').first(80)
    Crm::AgentGuidance.where(account: account, source: 'motor', status: %w[pending applied])
                      .where('created_at > ?', 30.days.ago).pluck(:rule)
                      .any? { |r| r.to_s.downcase.gsub(/[^a-z0-9à-ú]/, '').first(80) == key }
  end

  def finish_day(day, score, status:, verdict: nil, created: [], read: nil, error: nil) # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize, Metrics/CyclomaticComplexity
    row = { 'status' => status, 'at' => Time.current.iso8601, 'score' => score,
            'suggestions' => created.size, 'read' => read, 'error' => error.to_s.first(300).presence }
    if verdict
      row['summary'] = verdict['resumo'].to_s.first(800)
      row['won'] = Array(verdict['padroes_que_agendaram']).first(4).map { |t| t.to_s.first(240) }
      row['lost'] = Array(verdict['padroes_que_perderam']).first(4).map { |t| t.to_s.first(240) }
    end
    self.class.write! account do |cfg|
      st = cfg['state'] ||= {}
      (st['days'] ||= {})[day.iso8601] = row.compact
      why = st['why'] ||= {}
      created.each { |c| why[c['id'].to_s] = c.slice('why', 'confidence') }
      st['last_run_at'] = Time.current.iso8601
      prune!(st)
      cfg
    end
    { ok: status == 'ok', day: day.iso8601, status: status, suggestions: created.size, error: error }.compact
  end

  def prune!(state)
    cutoff = (TZ.today - KEEP_DAYS).iso8601
    (state['days'] || {}).delete_if { |date, _| date < cutoff }
    why = state['why'] || {}
    why.shift while why.size > 300
  end
end
