# 🗺️ MAPA DA JORNADA (item 173): tudo o que age em cada etapa do paciente —
# lembretes D-1/D-0, follow-up, réguas de mensagens, automações de coluna,
# campanhas agendadas e agentes — num único payload, para a tela da Jornada
# mostrar ao lado das mensagens dela, na mesma visão, sem rolar para o lado.
# As mensagens da jornada em si continuam vindo do index (a tela junta).
#
# Customização em agenda_config['journey']['map']:
#   stage_steps: { stage_id => etapa }     coluna do CRM → etapa da jornada
#   overrides:   { 'followup:12' => etapa | 'geral' }  item movido de etapa
#   hidden:      ['campaign:3', …]         item escondido do mapa
#   show:        { followup: true, … }     categorias visíveis
#   step_order:  ['lead', …]               ordem das etapas
#   step_labels: { lead: 'Novo contato' }  nomes das etapas
#   density:     'compact' | 'comfortable' · queue: 'side' | 'top' | 'hidden'
class Crm::Journey::MapService # rubocop:disable Metrics/ClassLength
  STEPS = Crm::JourneyMessage::STEPS
  GENERAL = 'geral'.freeze
  # ordem importa: "Cirurgia Agendada" é cirurgia (não consulta), "Pós Operatório" é pós-op
  STEP_HINTS = {
    'pos_op' => ['pos-op', 'posop', 'pos_op', 'pos op', 'operat'],
    'retorno' => %w[retorno recorr revis manuten],
    'cirurgia' => %w[cirurg],
    'orcamento' => %w[orcamento proposta negoci valor fechou fechamento],
    'consulta' => %w[consulta agend marcad compare avalia],
    'lead' => %w[lead novo entrada triagem interesse contato prospec]
  }.freeze
  KINDS = {
    'reminder' => { label: 'Lembrete da consulta', icon: 'i-lucide-bell-ring' },
    'followup' => { label: 'Follow-up', icon: 'i-lucide-timer' },
    'message_automation' => { label: 'Régua de mensagens', icon: 'i-lucide-list-ordered' },
    'column_automation' => { label: 'Automação da coluna', icon: 'i-lucide-workflow' },
    'campaign' => { label: 'Campanha', icon: 'i-lucide-megaphone' },
    'agent' => { label: 'Agente / robô', icon: 'i-lucide-bot' }
  }.freeze
  # agentes que fazem sentido numa etapa (nil = transversal, aparece na faixa "Geral")
  AGENT_STEPS = {
    'nps' => 'pos_op', 'closing' => 'orcamento', 'harvest' => 'lead', 'sales' => 'lead',
    'opportunity' => nil, 'stalled_cards' => nil, 'voice' => nil, 'calls' => nil
  }.freeze
  TRIGGER_LABELS = {
    'card_entered' => 'ao entrar na coluna', 'card_left' => 'ao sair da coluna', 'card_stalled' => 'cartão parado',
    'label_added' => 'ao receber etiqueta', 'label_removed' => 'ao perder etiqueta',
    'message_created' => 'ao chegar mensagem', 'value_added' => 'ao informar valor'
  }.freeze
  ACTION_LABELS = {
    'webhook' => 'chama webhook', 'n8n_flow' => 'dispara fluxo N8N', 'apply_label' => 'aplica etiqueta',
    'move_card' => 'move o cartão', 'log_timeline' => 'anota na linha do tempo', 'notify_team' => 'avisa o time',
    'meta_ads_event' => 'envia conversão à Meta', 'google_ads_conversion' => 'envia conversão ao Google',
    'send_form' => 'envia formulário', 'ai_analyze' => 'IA analisa a conversa', 'schedule_appointment' => 'agenda consulta',
    'set_value' => 'define valor', 'send_template' => 'envia mensagem-modelo', 'closing_extract' => 'IA lê o fechamento',
    'nps_score' => 'IA lê a nota (NPS)'
  }.freeze

  def initialize(account:)
    @account = account
  end

  def call
    items = collect_items
    {
      steps: ordered_steps,
      kinds: KINDS,
      stages: stages_json,
      stage_steps: effective_stage_steps,
      items: items.reject { |i| hidden.include?(i[:id]) || show[i[:kind]] == false },
      hidden_items: items.select { |i| hidden.include?(i[:id]) }.map { |i| i.slice(:id, :kind, :name) },
      map: map_config
    }
  end

  # ── configuração ────────────────────────────────────────────────────────
  def map_config
    @map_config ||= (settings.raw['map'] || {}).to_h
  end

  def show
    @show ||= KINDS.keys.index_with { true }.merge((map_config['show'] || {}).to_h)
  end

  def hidden
    @hidden ||= Array(map_config['hidden']).to_set(&:to_s)
  end

  def ordered_steps
    order = Array(map_config['step_order']).map(&:to_s).select { |k| STEPS.key?(k) }
    keys = (order + STEPS.keys).uniq
    labels = (map_config['step_labels'] || {}).to_h
    keys.map { |k| { key: k, label: labels[k].presence || STEPS[k] } }
  end

  # coluna do CRM → etapa (configurado, senão pelo nome)
  def effective_stage_steps
    @effective_stage_steps ||= stages.to_h do |stage|
      configured = (map_config['stage_steps'] || {})[stage.id.to_s].to_s
      [stage.id, STEPS.key?(configured) ? configured : guess_step(stage.name)]
    end
  end

  def guess_step(name)
    plain = I18n.transliterate(name.to_s).downcase
    STEP_HINTS.find { |_step, hints| hints.any? { |h| plain.include?(h) } }&.first || 'lead'
  end

  private

  def settings
    @settings ||= Crm::Journey::Settings.new(@account)
  end

  def stages
    @stages ||= Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id })
                          .includes(:pipeline).order('crm_pipelines.position, crm_stages.position').to_a
  end

  def stages_json
    stages.map { |s| { id: s.id, name: s.name, pipeline: s.pipeline.name, color: s.try(:color), step: effective_stage_steps[s.id] } }
  end

  def step_for_stage(stage_id)
    stage_id.present? ? effective_stage_steps[stage_id.to_i] : nil
  end

  def collect_items
    (reminder_items + followup_items + message_automation_items + column_automation_items + campaign_items + agent_items)
      .map { |item| apply_override(item) }
  end

  def apply_override(item)
    override = (map_config['overrides'] || {})[item[:id]].to_s
    item[:step] = override == GENERAL ? nil : override if STEPS.key?(override) || override == GENERAL
    item[:kind_label] = KINDS.dig(item[:kind], :label)
    item[:icon] = KINDS.dig(item[:kind], :icon)
    item
  end

  # ── fontes ──────────────────────────────────────────────────────────────
  REMINDER_NAMES = { 0 => 'D-0 · dia da consulta', 1 => 'D-1 · véspera da consulta' }.freeze

  # item 253: todos os lembretes da Confirmação de consulta (0 a 7 dias antes);
  # véspera e dia aparecem sempre (como antes), mais os outros salvos
  def reminder_items # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
    cfg = (CrmSetting.find_by(account: @account)&.agenda_config || {})['appointment_reminders'] || {}
    keys = (Crm::AppointmentReminderSendJob::REGUAS & cfg.keys) | %w[d1 d0]
    keys.sort_by { |k| -Crm::AppointmentReminderSendJob.days_of(k) }.map do |key|
      days = Crm::AppointmentReminderSendJob.days_of(key)
      name = REMINDER_NAMES[days] || "D-#{days} · #{days} dias antes"
      rule = (cfg[key] || {}).to_h
      hour = rule['hour'].presence || Crm::AppointmentReminderSendJob.default_hour(key)
      { id: "reminder:#{key}", kind: 'reminder', name: "Lembrete #{name}", step: 'consulta',
        enabled: rule['enabled'] == true, when_label: "às #{format('%02d', hour.to_i)}:00",
        detail: rule['message_preview'].to_s.truncate(90).presence || 'mensagem-modelo do lembrete',
        route: { name: 'cevico_automations', query: { tab: 'agentes', agent: 'confirmacao' } } }
    end
  end

  def followup_items
    Crm::FollowupBot.where(account: @account).includes(:stage).order(:name).map do |bot|
      steps = Array(bot.steps)
      first = steps.first || {}
      { id: "followup:#{bot.id}", kind: 'followup', name: bot.name, step: step_for_stage(bot.stage_id) || 'lead',
        enabled: bot.active, when_label: "#{steps.size} cutucada(s)#{first_delay_label(first)}",
        detail: bot.stage ? "coluna #{bot.stage.name}" : 'todas as colunas', stage_id: bot.stage_id,
        route: { name: 'cevico_automations', query: { tab: 'robos' } } }
    end
  end

  def first_delay_label(step)
    value = step['delay_value'] || step['delay_hours']
    return '' if value.blank?

    unit = { 'minutes' => 'min', 'hours' => 'h', 'days' => 'd' }[step['delay_unit'].to_s] || 'h'
    " · 1ª após #{value}#{unit}"
  end

  def message_automation_items
    Crm::MessageAutomation.where(account: @account).includes(:trigger_stage).order(:name).map do |rule|
      step = step_for_stage(rule.trigger_stage_id) || (rule.trigger_label.present? ? guess_step(rule.trigger_label) : 'lead')
      { id: "message_automation:#{rule.id}", kind: 'message_automation', name: rule.name, step: step,
        enabled: rule.active, when_label: "#{rule.delay_days} dia(s) depois", stage_id: rule.trigger_stage_id,
        detail: rule.trigger_stage ? "na coluna #{rule.trigger_stage.name}" : "com a etiqueta #{rule.trigger_label}",
        route: { name: 'crm_campaigns', query: { tab: 'automations' } } }
    end
  end

  def column_automation_items # rubocop:disable Metrics/AbcSize
    Crm::Automation.joins(stage: :pipeline).where(crm_pipelines: { account_id: @account.id })
                   .includes(:stage).order('crm_stages.position, crm_automations.id').map do |auto|
      { id: "column_automation:#{auto.id}", kind: 'column_automation', name: auto.name.presence || ACTION_LABELS[auto.action_type],
        step: step_for_stage(auto.stage_id) || 'lead', enabled: auto.active, stage_id: auto.stage_id,
        when_label: [TRIGGER_LABELS[auto.trigger_type], delay_label(auto.delay_minutes)].compact.join(' · '),
        detail: "#{auto.stage.name}: #{ACTION_LABELS[auto.action_type] || auto.action_type}",
        route: { name: 'cevico_automations', query: { tab: 'programacao' } } }
    end
  end

  def delay_label(minutes)
    m = minutes.to_i
    return nil if m.zero?
    return "#{m} min" if m < 60
    return "#{m / 60} h" if m < 1440

    "#{m / 1440} d"
  end

  def campaign_items
    Crm::Campaign.where(account: @account, status: %w[draft scheduled processing]).order(:scheduled_at, :name).map do |camp|
      stage_id = Array((camp.audience || {})['include_stage_ids']).first
      { id: "campaign:#{camp.id}", kind: 'campaign', name: camp.name, step: step_for_stage(stage_id) || 'lead',
        enabled: camp.status != 'draft', stage_id: stage_id,
        when_label: camp.scheduled_at ? "agendada #{camp.scheduled_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')}" : camp.status,
        detail: camp.message_preview.to_s.truncate(90).presence || 'campanha de WhatsApp',
        route: { name: 'crm_campaigns' } }
    end
  end

  def agent_items
    AGENT_STEPS.filter_map do |key, step|
      flow = Crm::FlowMap::Registry.find_flow(key)
      next unless flow

      data = flow.to_h(@account)
      live = data[:live] || {}
      { id: "agent:#{key}", kind: 'agent', name: data[:name], step: step, enabled: live[:enabled],
        when_label: data.dig(:trigger, :label).to_s, detail: data[:what].to_s.truncate(110),
        live: live.slice(:counters, :note, :last_run_at), route: agent_route(data[:config] || {}) }
    end
  end

  def agent_route(config)
    return { name: config[:route] } if config[:route]

    { name: 'cevico_automations', query: { tab: config[:tab], anchor: config[:anchor] }.compact }
  end
end
