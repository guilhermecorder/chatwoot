# 🧑‍🏫 CONSULTOR SUPERIOR (item 414, 24/11/2026): configuração, gatilhos e
# contador. Quem pede a segunda opinião é o Crm::ResponderConsultant.
#
# A ideia: o motor PRINCIPAL do atendente (o barato) responde a tudo; em
# situações definidas pelo SISTEMA, a resposta dele é segurada e um motor
# SUPERIOR diz qual deve ser a resposta final. O principal não precisa "saber
# que não sabe": quem decide a hora de consultar são as regras abaixo.
#
# A config mora, POR AGENTE, em ai_config['agents'][agente]['consultor']:
#   { 'enabled' => true,
#     'model' => 'claude-sonnet-5',        ← qualquer modelo com a chave salva
#     'mode' => 'sombra' | 'ativo',        ← sombra = só registra; ativo = vale a resposta do consultor
#     'triggers' => { 'chamar_humano' => true, 'vaga_invalida' => true, 'sem_pergunta' => true },
#     'question_stages' => ['recepcao', …],← etapas em que resposta sem pergunta conta como fraca
#     'inbox_ids' => [12],                 ← só nestas caixas (vazio = em todas as que o agente lê)
#     'tool' => false,                     ← ferramenta consultar_superior para o principal (só no modo ativo)
#     'daily_cap' => 50,                   ← teto de consultas por dia (conversas de paciente)
#     'timeout' => 40, 'effort' => 'medium' }
# Sem a chave, com enabled != true, com modelo em branco ou sem a chave do
# fornecedor do modelo = DESLIGADO: o atendente se comporta exatamente como antes.
#
# O CONTADOR fica em ai_config["<agente>_state"]['consultor_days'] (35 dias),
# um registro por dia no fuso de São Paulo. Testes do 🧪 Testar agente entram
# em 'testes' e NÃO gastam o teto do dia.
module Crm::ConsultantConfig # rubocop:disable Metrics/ModuleLength
  module_function

  CONFIG_KEY = 'consultor'.freeze
  STATE_KEY = 'consultor_days'.freeze
  NOTE_KEY = 'cevico_ia_consultor'.freeze
  MODES = %w[sombra ativo].freeze
  # gatilho => frase curta (registro, nota, tela)
  TRIGGERS = {
    'chamar_humano' => 'chamou a equipe sem urgência clínica',
    'vaga_invalida' => 'ia agendar em um horário que não validou',
    'sem_pergunta' => 'resposta vazia ou sem pergunta'
  }.freeze
  TOOL_TRIGGER = 'ferramenta'.freeze
  TRIGGER_LABELS = TRIGGERS.merge(TOOL_TRIGGER => 'o principal pediu orientação').freeze
  # etapas do roteiro de vendas: toda resposta conduz ao próximo passo com uma pergunta
  DEFAULT_QUESTION_STAGES = %w[recepcao sondagem autoridade orcamento objecoes agendamento].freeze
  EFFECT_LABELS = {
    'evitou_equipe' => 'não precisava chamar a equipe', 'confirmou_equipe' => 'confirmou: é caso para a equipe',
    'corrigiu_vaga' => 'corrigiu para um horário livre', 'ofereceu_outro_horario' => 'ofereceu outro horário',
    'vaga_ainda_invalida' => 'também ficou sem horário válido', 'completou' => 'completou a resposta',
    'manteve' => 'manteve a resposta do principal', 'respondeu' => 'respondeu no lugar do principal',
    'orientou' => 'orientou o principal'
  }.freeze
  DEFAULT_CAP = 50
  MAX_CAP = 5000
  DEFAULT_TIMEOUT = 40
  TIMEOUT_RANGE = (10..90)
  DEFAULT_EFFORT = 'medium'.freeze
  KEEP_DAYS = 35
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  # a config do agente com todos os campos preenchidos (o que falta = padrão)
  def normalize(agent_config) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    raw = agent_config.is_a?(Hash) ? agent_config[CONFIG_KEY] : nil
    raw = {} unless raw.is_a?(Hash)
    triggers = raw['triggers'].is_a?(Hash) ? raw['triggers'] : {}
    stages = Array(raw['question_stages']).map(&:to_s) & Crm::ResponderAgentService::ETAPAS
    {
      'enabled' => raw['enabled'] == true,
      'model' => raw['model'].to_s.strip,
      'mode' => MODES.include?(raw['mode']) ? raw['mode'] : 'sombra',
      # gatilho nunca configurado = ligado (quem liga o consultor já sai com os três)
      'triggers' => TRIGGERS.keys.index_with { |key| triggers[key] != false },
      'question_stages' => raw.key?('question_stages') ? stages : DEFAULT_QUESTION_STAGES,
      'inbox_ids' => inbox_ids(raw['inbox_ids']),
      'tool' => raw['tool'] == true,
      'daily_cap' => raw['daily_cap'].to_i.positive? ? [raw['daily_cap'].to_i, MAX_CAP].min : DEFAULT_CAP,
      'timeout' => TIMEOUT_RANGE.cover?(raw['timeout'].to_i) ? raw['timeout'].to_i : DEFAULT_TIMEOUT,
      'effort' => Crm::AiAgentConfig::EFFORTS.include?(raw['effort']) ? raw['effort'] : DEFAULT_EFFORT
    }
  end

  def inbox_ids(raw)
    Array(raw).map(&:to_i).select(&:positive?).uniq
  end

  # a config LIGADA e pronta para rodar agora, ou nil (= desligado).
  # inbox_id = a caixa da conversa: com caixas escolhidas, só vale nelas
  # (o 🧪 Testar agente não passa caixa: lá o consultor vale sempre).
  def active(agent_config, ai_config, inbox_id: nil)
    config = normalize(agent_config)
    return nil unless config['enabled'] && Crm::LlmCatalog.usable?(ai_config, config['model'])
    return nil if inbox_id && config['inbox_ids'].any? && config['inbox_ids'].exclude?(inbox_id.to_i)

    config
  end

  # limpa o que chegou da tela (o que não veio fica como estava em `current`)
  def sanitize(raw, current = {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    raw = raw.deep_stringify_keys
    clean = normalize(CONFIG_KEY => current)
    bool = ->(value) { ActiveModel::Type::Boolean.new.cast(value) == true }
    clean['enabled'] = bool.call(raw['enabled']) if raw.key?('enabled')
    clean['model'] = raw['model'].to_s.strip if raw.key?('model')
    clean['mode'] = raw['mode'].to_s if MODES.include?(raw['mode'].to_s)
    clean['tool'] = bool.call(raw['tool']) if raw.key?('tool')
    if raw['triggers'].is_a?(Hash)
      TRIGGERS.each_key { |key| clean['triggers'][key] = bool.call(raw['triggers'][key]) if raw['triggers'].key?(key) }
    end
    clean['question_stages'] = Array(raw['question_stages']).map(&:to_s) & Crm::ResponderAgentService::ETAPAS if raw.key?('question_stages')
    clean['inbox_ids'] = inbox_ids(raw['inbox_ids']) if raw.key?('inbox_ids')
    clean['daily_cap'] = raw['daily_cap'].to_i.clamp(1, MAX_CAP) if raw['daily_cap'].to_i.positive?
    clean['timeout'] = raw['timeout'].to_i.clamp(TIMEOUT_RANGE.first, TIMEOUT_RANGE.last) if raw['timeout'].to_i.positive?
    clean['effort'] = raw['effort'].to_s if Crm::AiAgentConfig::EFFORTS.include?(raw['effort'].to_s)
    clean
  end

  # ── CONTADOR ────────────────────────────────────────────────────────────
  def today
    TZ.now.to_date.to_s
  end

  def state_key(agent_key)
    "#{agent_key}_state"
  end

  def days(ai_config, agent_key)
    list = (ai_config || {}).dig(state_key(agent_key), STATE_KEY)
    list.is_a?(Hash) ? list : {}
  end

  # pede UMA vaga no teto de hoje, de forma atômica (a trava é a da linha do
  # crm_settings). true = pode consultar. Teste do simulador não gasta o teto.
  # Qualquer falha aqui = sem consulta (vale a resposta do principal).
  def reserve!(account, agent_key, cap, test: false)
    return true if test

    granted = false
    update_day(account, agent_key) do |day|
      if day['consultas'].to_i < cap
        granted = true
        day['consultas'] = day['consultas'].to_i + 1
      else
        day['barradas'] = day['barradas'].to_i + 1
      end
    end
    granted
  rescue StandardError => e
    Rails.logger.warn "[Crm::ConsultantConfig] teto do dia: #{e.class}: #{e.message}"
    false
  end

  # soma o desfecho de UMA consulta no dia (gatilho, efeito, custo, se mudou)
  def record!(account, agent_key, record) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    update_day(account, agent_key) do |day|
      day['testes'] = day['testes'].to_i + 1 if record['teste']
      day['custo_usd'] = (day['custo_usd'].to_f + record['custo_usd'].to_f).round(6)
      bump(day, 'gatilhos', record['gatilho'])
      case record['status']
      when 'ok'
        bump(day, 'efeitos', record['efeito'])
        day['mudou'] = day['mudou'].to_i + 1 if record['mudou']
        day['aplicadas'] = day['aplicadas'].to_i + 1 if record['aplicado']
      when 'falhou' then day['falhas'] = day['falhas'].to_i + 1
      when 'pulou' then day['puladas'] = day['puladas'].to_i + 1
      end
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::ConsultantConfig] contador: #{e.class}: #{e.message}"
  end

  def bump(day, group, key)
    return if key.blank?

    day[group] = (day[group].is_a?(Hash) ? day[group] : {}).merge(key => day.dig(group, key).to_i + 1)
  end

  def update_day(account, agent_key)
    Cevico::SettingMerge.merge_key!(account, :ai_config, state_key(agent_key)) do |state|
      list = state[STATE_KEY].is_a?(Hash) ? state[STATE_KEY] : {}
      day = (list[today] || {}).deep_dup
      yield(day)
      state[STATE_KEY] = list.merge(today => day).sort.last(KEEP_DAYS).to_h
      state
    end
  end

  # resumo para a tela e para o Laboratório: hoje + soma dos últimos N dias
  def summary(ai_config, agent_key, span: 7)
    list = days(ai_config, agent_key)
    since = (TZ.now.to_date - (span - 1)).to_s
    recent = list.select { |date, _| date >= since }
    config = normalize((ai_config || {}).dig('agents', agent_key))
    {
      today: day_view(list[today]), cap: config['daily_cap'], span: span, total: day_view(sum_days(recent.values)),
      daily: recent.sort.map { |date, day| day_view(day).merge(date: date) }
    }
  end

  COUNT_KEYS = %w[consultas barradas testes mudou aplicadas falhas puladas].freeze
  GROUP_KEYS = %w[gatilhos efeitos].freeze

  def sum_days(list)
    list.each_with_object({}) do |day, total|
      COUNT_KEYS.each { |key| total[key] = total[key].to_i + day[key].to_i }
      total['custo_usd'] = (total['custo_usd'].to_f + day['custo_usd'].to_f).round(6)
      GROUP_KEYS.each do |group|
        total[group] = (total[group] || {}).merge(day[group] || {}) { |_key, old, new| old.to_i + new.to_i }
      end
    end
  end

  def day_view(day)
    day ||= {}
    {
      consultas: day['consultas'].to_i, barradas: day['barradas'].to_i, testes: day['testes'].to_i, mudou: day['mudou'].to_i,
      aplicadas: day['aplicadas'].to_i, falhas: day['falhas'].to_i, puladas: day['puladas'].to_i,
      custo_usd: day['custo_usd'].to_f.round(4), gatilhos: day['gatilhos'] || {}, efeitos: day['efeitos'] || {}
    }
  end

  # ── TEXTO DO REGISTRO (nota interna e registro do card) ─────────────────
  # "🧑‍🏫 Consultor (Claude Sonnet 5 · sombra) · motivo: chamou a equipe sem urgência clínica → …"
  def headline(record)
    return '' if record.blank?

    model = Crm::LlmCatalog.label(record['modelo'])
    reason = TRIGGER_LABELS[record['gatilho']] || record['gatilho']
    "🧑‍🏫 Consultor superior (#{model} · modo #{record['modo']}) · motivo: #{reason} → #{outcome_text(record)}"
  end

  def outcome_text(record) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    case record['status']
    when 'teto' then 'teto de consultas do dia atingido: não consultou, valeu a resposta do principal'
    when 'pulou' then "não consultou (#{record['erro']}): valeu a resposta do principal"
    when 'falhou' then "o consultor falhou (#{record['erro']}): valeu a resposta do principal"
    else
      effect = EFFECT_LABELS[record['efeito']] || record['efeito'].to_s
      return effect if record['gatilho'] == TOOL_TRIGGER
      return "#{effect}; valeu a resposta do consultor" if record['aplicado']
      return "#{effect}; em sombra, valeu a resposta do principal" if record['mudou'] && record['modo'] == 'sombra'

      record['mudou'] ? "#{effect}; valeu a resposta do principal" : effect
    end
  end

  # linhas da nota interna: o que o principal ia fazer × o que o consultor devolveu
  def note_lines(record) # rubocop:disable Metrics/CyclomaticComplexity
    return [] if record.blank?

    lines = [headline(record)]
    lines << "Dúvida do principal: #{record['duvida']}" if record['duvida'].present?
    lines << "Orientação do consultor: #{record['orientacao']}" if record['orientacao'].present?
    return lines unless record['status'] == 'ok' && record['mudou']

    lines << "O principal (#{Crm::LlmCatalog.label(record['principal'])}) ia responder: #{snapshot_text(record['antes'])}"
    lines << "O consultor respondeu: #{snapshot_text(record['depois'])}"
    lines << 'A tarefa que o principal abriu para a equipe continua aberta no Meu Painel.' if record['tarefa_aberta'] && record['aplicado']
    lines
  end

  def snapshot_text(snapshot) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    snapshot ||= {}
    return "(#{snapshot['erro']})" if snapshot['erro'].present?

    text = Array(snapshot['mensagens']).join(' / ').presence || '(sem mensagem)'
    flags = []
    if snapshot['agendar']
      slot = snapshot['agendamento'] || {}
      flags << "agendaria #{slot['dia']} #{slot['hora']} #{slot['unidade']}".squish
    end
    flags << 'chamaria a equipe' if snapshot['chamar_humano']
    flags << 'cancelaria a consulta' if snapshot['cancelar']
    flags << 'encerraria' if snapshot['pausar']
    flags.any? ? "#{text.truncate(500)} [#{flags.join(' · ')}]" : text.truncate(500)
  end
end
