# 🧪 LABORATÓRIO DE ATENDIMENTO (item 403, 23/11, só admin): o ambiente de
# comparação dos testes A/B dos atendentes do WhatsApp — para DECIDIR.
#   show        → o teste de agora (ou um do histórico, ?test=id) com o funil
#                 das duas variantes, custo, confiança, a conta da decisão,
#                 o que muda entre os prompts e a lista dos testes anteriores
#   finish      → encerra o teste, anota a decisão e (se pedido) ADOTA a B:
#                 o motor dela vira o do cartão e/ou o Roteiro 2 vira o oficial
#                 (com foto do Roteiro antigo: "voltar para esta" desfaz)
#   copy_script → o Roteiro 2 recomeça como cópia exata do Roteiro 1, para o
#                 próximo teste mudar UMA coisa só
#   mark / unmark   → 📍 marco do atendimento (24/11): a data em que algo grande
#                     mudou; o Laboratório compara ANTES × DEPOIS por caixa
#   restore_point   → 🔙 volta o atendimento ao formato de antes de 24/11
#                     (Crm::AttendanceRestorePoint), com foto do que havia
# Quem liga/desliga e escolhe a variante B continua sendo o cartão do agente
# (settings#save_ai_experiment). A matemática mora em Crm::EngineExperiment.
class Api::V1::Accounts::Crm::AttendanceLabsController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  include Crm::AccessControl

  AGENTS = {
    'atendente_agendamento' => 'Atendente de Agendamento',
    'atendente_pos' => 'Atendente Pós-agendamento',
    'atendente_pos_op' => 'Atendente de Pós-operatório'
  }.freeze
  BACKUP_KEY = 'script_v2_backup'.freeze

  before_action :admin_only
  before_action :set_agent

  def show
    render json: lab_json
  end

  # 📍 anota um marco (título obrigatório; `at` em branco = agora)
  def mark # rubocop:disable Metrics/AbcSize
    title = params[:title].to_s.strip
    return render json: { error: 'Dê um nome ao marco.' }, status: :unprocessable_entity if title.blank?

    at = params[:at].present? ? Crm::AttendanceMilestones.parse(params[:at]) : Time.current
    return render json: { error: 'Data do marco inválida.' }, status: :unprocessable_entity if at.nil? || at > 1.minute.from_now

    Crm::AttendanceMilestones.add!(Current.account, title: title, note: params[:note], at: at.iso8601, by: Current.user&.name)
    @settings = nil
    render json: lab_json
  end

  def unmark
    Crm::AttendanceMilestones.remove!(Current.account, params[:id])
    @settings = nil
    render json: lab_json
  end

  # 🔙 volta o atendimento ao formato de antes de 24/11 (pede confirmação escrita na tela)
  def restore_point
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render json: { error: 'Confirme para voltar ao atendimento antigo.' }, status: :unprocessable_entity
    end

    Crm::AttendanceRestorePoint.apply!(Current.account, by: Current.user)
    @settings = nil
    render json: lab_json
  end

  def finish # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    experiment = agent_config[Crm::EngineExperiment::CONFIG_KEY] || {}
    # sem teste, ou com a B ainda igual à A (nunca chegou a ser um teste): nada para encerrar
    unless experiment['started_at'].present? && Crm::EngineExperiment.variant_b?(experiment)
      return render json: { error: 'Este atendente não tem teste para encerrar.' }, status: :unprocessable_entity
    end
    return render json: { error: 'Este teste já foi encerrado.' }, status: :unprocessable_entity if experiment['ended_at'].present?

    decision = Crm::EngineExperiment::ARMS.include?(params[:decision].to_s) ? params[:decision].to_s : nil
    adopt = decision == 'b' && ActiveModel::Type::Boolean.new.cast(params[:apply]) == true
    report = Crm::EngineExperiment.report(Current.account, @agent, experiment['started_at'])
    entry = Crm::EngineExperiment.history_entry(experiment, @agent, agent_config, by: Current.user&.name, decision: decision, note: params[:note])
                                 .merge('snapshot' => Crm::EngineExperiment.snapshot(report), 'adopted' => adopt)

    adopt_script! if adopt && Crm::EngineExperiment.script_b(experiment) == 'v2'
    motor = adopt && experiment['model_b'].present? ? adopted_motor(experiment) : nil
    Cevico::SettingMerge.merge!(settings, :ai_config) do |fresh|
      fresh['agents'] ||= {}
      agent = fresh['agents'][@agent] || {}
      current = agent[Crm::EngineExperiment::CONFIG_KEY] || {}
      agent[Crm::EngineExperiment::CONFIG_KEY] = current.merge('enabled' => false, 'ended_at' => entry['ended_at'])
      agent[Crm::EngineExperiment::HISTORY_KEY] = Crm::EngineExperiment.push_history(agent, entry)
      agent.merge!(motor) if motor
      fresh['agents'][@agent] = agent
      fresh
    end
    @settings = nil
    render json: lab_json
  end

  def copy_script # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    running = Crm::LlmEngines::OPENAI_AGENT_KEYS.find do |key|
      experiment = Crm::EngineExperiment.active(agents_config[key])
      experiment && Crm::EngineExperiment.script_b(experiment) == 'v2'
    end
    if running
      message = "O #{AGENTS[running]} está com um teste ligado lendo o Roteiro 2. Encerre o teste antes de recomeçar o Roteiro 2."
      return render json: { error: message }, status: :unprocessable_entity
    end

    account = Current.account
    script = Crm::CevicoScript::SECTIONS.to_h { |section| [section['key'], Crm::CevicoScript.section_text(account, section['key'], 'v1')] }
    stages = Crm::LlmEngines::OPENAI_AGENT_KEYS.index_with { |key| Crm::CevicoScript.stage_prompt(account, key, 'v1') }
    Cevico::SettingMerge.merge!(settings, :ai_config) do |fresh|
      fresh['agents'] ||= {}
      # um degrau de "desfazer": o Roteiro 2 de antes fica guardado
      fresh[BACKUP_KEY] = { 'at' => Time.current.iso8601, 'by' => Current.user&.name, 'script_v2' => fresh['script_v2'],
                            'prompts' => stages.keys.index_with { |key| fresh.dig('agents', key, 'prompt_v2') } }
      fresh['script_v2'] = script.merge('updated_at' => Time.current.iso8601)
      stages.each { |key, text| fresh['agents'][key] = (fresh['agents'][key] || {}).merge('prompt_v2' => text) }
      fresh
    end
    @settings = nil
    render json: lab_json
  end

  private

  def admin_only
    render json: { error: 'Apenas administradores.' }, status: :forbidden unless Current.account_user&.administrator?
  end

  def set_agent
    @agent = AGENTS.key?(params[:agent].to_s) ? params[:agent].to_s : AGENTS.keys.first
  end

  def settings
    @settings ||= CrmSetting.find_or_create_by!(account: Current.account)
  end

  def agents_config
    (settings.ai_config || {})['agents'] || {}
  end

  def agent_config
    agents_config[@agent] || {}
  end

  # O Roteiro 2 (o que a variante B leu) vira o oficial: o Roteiro inteiro e os
  # passos DESTE atendente. Antes, foto do que estava valendo — a tela de
  # versões do Roteiro ("voltar para esta") desfaz em um toque.
  def adopt_script!
    account = Current.account
    note = 'antes de adotar o Roteiro 2 (variante B do teste A/B)'
    Crm::ScriptVersion.snapshot!(account, kind: 'script', note: note, by: Current.user)
    Crm::ScriptVersion.snapshot!(account, kind: 'stage', agent_key: @agent, note: note, by: Current.user)
    script = Crm::CevicoScript::SECTIONS.to_h { |section| [section['key'], Crm::CevicoScript.section_text(account, section['key'], 'v2')] }
    stage = Crm::CevicoScript.stage_prompt(account, @agent, 'v2')
    Crm::ScriptVersion.write_script!(account, script)
    Crm::ScriptVersion.write_stage_prompt!(account, @agent, stage)
  end

  def lab_json # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    experiment = agent_config[Crm::EngineExperiment::CONFIG_KEY] || {}
    history = Crm::EngineExperiment.history(agent_config)
    viewing = history.find { |entry| entry['id'] == params[:test].to_s } if params[:test].present?
    {
      agent: @agent,
      agents: AGENTS.map { |key, name| agent_row(key, name) },
      test: viewing ? past_test(viewing) : current_test(experiment),
      report: Crm::EngineExperiment.report(Current.account, @agent, viewing&.dig('id')),
      history: history,
      inboxes: inbox_rows(viewing ? viewing['inboxes'] : experiment['inboxes']),
      prompt: prompt_compare(experiment, viewing),
      script_v2_backup_at: (settings.ai_config || {}).dig(BACKUP_KEY, 'at'),
      usd_brl: usd_rate,
      # 📍 24/11: marcos do atendimento + antes × depois do marco escolhido (?marco=id; padrão: o mais novo)
      marcos: Crm::AttendanceMilestones.list(Current.account),
      before_after: before_after_json,
      restore_point: Crm::AttendanceRestorePoint.summary(Current.account)
    }
  end

  def before_after_json
    marco = Crm::AttendanceMilestones.find(Current.account, params[:marco])
    return nil if marco.nil?

    at = Crm::AttendanceMilestones.parse(marco['at'])
    Crm::AttendanceBeforeAfter.new(Current.account, at: at).call&.merge(marco: marco)
  end

  def agent_row(key, name)
    config = agents_config[key] || {}
    experiment = config[Crm::EngineExperiment::CONFIG_KEY] || {}
    running = Crm::EngineExperiment.active(config).present?
    { key: key, name: name, enabled: config['enabled'] == true, running: running,
      kind: running ? Crm::EngineExperiment.kind(experiment, Crm::EngineExperiment.model_a(key, config), staged: staged?(config)) : nil,
      history: Crm::EngineExperiment.history(config).size }
  end

  def current_test(experiment)
    model_a = Crm::EngineExperiment.model_a(@agent, agent_config)
    ready = Crm::EngineExperiment.variant_b?(experiment)
    {
      id: experiment['started_at'], current: true, name: experiment['name'],
      enabled: experiment['enabled'] == true, ended_at: experiment['ended_at'],
      kind: ready ? Crm::EngineExperiment.kind(experiment, model_a, staged: staged?(agent_config)) : nil,
      stages: stage_rows(experiment),
      model_a: model_a, model_b: experiment['model_b'].presence || model_a,
      script_b: Crm::EngineExperiment.script_b(experiment), updated_by: experiment['updated_by']
    }
  end

  # 🧭 item 405: o que "adotar o motor da B" grava. Sem motor por coluna = o
  # modelo do cartão, como antes. Com motor por coluna = o motor da B entra no
  # MAPA, só nas colunas em que ela trocou (todas, se não havia escolha); o
  # resto do mapa e o modelo do cartão ficam como estão.
  def adopted_motor(experiment)
    map = Crm::StageEngine.config(agent_config)
    swap = Crm::EngineExperiment.stages_b(experiment)
    return { 'model' => experiment['model_b'] } if map.empty? && swap.empty?

    slots = swap.presence || Crm::StageEngine.rows(Current.account, agent_config).pluck(:slot)
    { Crm::StageEngine::CONFIG_KEY => map.merge(slots.index_with { experiment['model_b'] }) }
  end

  def staged?(config)
    Crm::StageEngine.config(config).any?
  end

  # 🧭 item 405: o mapa de motor por coluna das duas variantes, coluna a coluna.
  # A = a escolha da coluna (ou o modelo do cartão); B = igual à A, menos nas
  # colunas em que ela troca o motor.
  def stage_rows(experiment)
    model_a = Crm::EngineExperiment.model_a(@agent, agent_config)
    swap = Crm::EngineExperiment.stages_b(experiment)
    Crm::StageEngine.rows(Current.account, agent_config).map do |row|
      first = row[:model] || model_a
      swaps = experiment['model_b'].present? && (swap.empty? || swap.include?(row[:slot]))
      { slot: row[:slot], name: row[:name], a: first, b: swaps ? experiment['model_b'] : first }
    end
  end

  def past_test(entry)
    entry.slice('id', 'name', 'kind', 'model_a', 'model_b', 'script_b', 'ended_at', 'decision', 'note', 'ended_by', 'adopted')
         .symbolize_keys.merge(current: false, enabled: false, stages: [])
  end

  def inbox_rows(modes)
    ids = Array(agent_config['inbox_ids']).map(&:to_i)
    names = Current.account.inboxes.where(id: ids).pluck(:id, :name).to_h
    ids.filter_map do |id|
      next if names[id].nil?

      { id: id, name: names[id], mode: Crm::EngineExperiment::MODES.include?((modes || {})[id.to_s]) ? modes[id.to_s] : 'a' }
    end
  end

  # o que MUDA entre o prompt da A (Roteiro 1) e o da B (Roteiro 2), seção por
  # seção; e se alguém mexeu em algum dos dois depois que o teste começou
  def prompt_compare(experiment, viewing)
    account = Current.account
    sections = Crm::CevicoScript::SECTIONS.map do |section|
      { key: section['key'], title: section['title'],
        a: Crm::CevicoScript.section_text(account, section['key'], 'v1'), b: Crm::CevicoScript.section_text(account, section['key'], 'v2') }
    end
    sections << { key: 'stage', title: "Passos do #{AGENTS[@agent]}",
                  a: Crm::CevicoScript.stage_prompt(account, @agent, 'v1'), b: Crm::CevicoScript.stage_prompt(account, @agent, 'v2') }
    different = sections.reject { |section| section[:a].to_s.strip == section[:b].to_s.strip }
    {
      total: sections.size, different: different,
      changed_since_start: viewing ? {} : prompt_changed(experiment)
    }
  end

  def prompt_changed(experiment)
    saved = experiment['digests']
    return {} unless saved.is_a?(Hash) && experiment['started_at'].present? && experiment['ended_at'].blank?

    now = Crm::EngineExperiment.digests(Current.account, @agent, experiment)
    Crm::EngineExperiment::ARMS.index_with { |arm| saved[arm].present? && saved[arm] != now[arm] }
  end

  def usd_rate
    known = Crm::UsdRateService.last_known
    known.is_a?(Hash) ? (known[:rate] || known['rate']).to_f.nonzero? : nil
  rescue StandardError
    nil
  end
end
