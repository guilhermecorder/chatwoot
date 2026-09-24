# 🔧 Um atendente de IA REMARCOU ou CANCELOU uma consulta pelo WhatsApp
# (rodada 192, ferramentas ao vivo) → aviso no Radar do Meu Painel, para a
# equipe conferir na Agenda. Entra na mesma lista dos avisos do Radar de
# Oportunidades (ai_config opportunity_state.alerts), kinds 'agente_remarcou'
# e 'agente_cancelou'; some sozinho após 24 h. Espelha Crm::Calls::RadarAlert.
# Direcionado à pessoa que cuida da consulta (task.assignee_id); sem
# responsável = todos veem.
class Crm::AgentAlert
  # item 217: 'nao_confirmou' = paciente respondeu NÃO ao lembrete da véspera
  KINDS = %w[agente_remarcou agente_cancelou nao_confirmou].freeze
  TTL = 24.hours
  MAX_ALERTS = 30
  TZ = Crm::AgendaSlots::TZ
  WEEKDAYS_SHORT = %w[dom seg ter qua qui sex sáb].freeze
  AGENT_NAMES = { 'atendente_agendamento' => 'Atendente de Agendamento', 'atendente_pos' => 'Atendente Pós-agendamento' }.freeze

  def self.push(account:, kind:, task:, conversation:, agent_key:)
    raise ArgumentError, "kind inválido: #{kind}" unless KINDS.include?(kind.to_s)

    new(account: account, kind: kind.to_s, task: task, conversation: conversation, agent_key: agent_key.to_s).push
  rescue StandardError => e
    Rails.logger.warn("[CEVICO agente] aviso do Radar não gravado: #{e.message}")
    nil
  end

  # o aviso continua valendo? (24 h, e a consulta ainda existe nesta conta)
  def self.still_open?(account, alert)
    created = Time.zone.parse(alert['created_at'].to_s)
    return false if created.nil? || created < TTL.ago

    account.tasks.exists?(id: alert['task_id'])
  rescue ArgumentError
    false
  end

  def initialize(account:, kind:, task:, conversation:, agent_key:)
    @account = account
    @kind = kind
    @task = task
    @conversation = conversation
    @agent_key = agent_key
  end

  def push
    settings = CrmSetting.find_or_create_by!(account: @account)
    settings.with_lock do
      cfg = settings.ai_config || {}
      state = cfg['opportunity_state'] || {}
      alerts = Array(state['alerts']).reject { |a| a['kind'] == @kind && a['task_id'] == @task.id }
      alerts << build
      state['alerts'] = alerts.last(MAX_ALERTS)
      cfg['opportunity_state'] = state
      settings.update!(ai_config: cfg)
      alerts.last
    end
  end

  private

  def build
    contact = @task.contact || @conversation.contact
    {
      'kind' => @kind, 'task_id' => @task.id,
      'conversation_id' => @conversation.display_id,
      'contact_id' => contact&.id,
      'contact_name' => patient_name,
      # telefone da CONSULTA (pode ser de um familiar), não o do WhatsApp que pediu
      'phone' => @task.phone.presence || contact&.phone_number,
      'stage_name' => stage_name,
      'motivo' => motivo, 'acao' => @kind == 'nao_confirmou' ? 'Ligar para o paciente' : 'Conferir na Agenda',
      'user_id' => @task.assignee_id, 'user_name' => @task.assignee&.name,
      'created_at' => Time.current.iso8601
    }
  end

  def patient_name
    @task.title.to_s.sub(/\AConsulta:\s*/i, '').strip.presence || 'Paciente'
  end

  def stage_name
    case @kind
    when 'agente_cancelou' then 'Consulta cancelada'
    when 'nao_confirmou' then 'Não confirmou a consulta'
    else 'Consulta remarcada'
    end
  end

  def motivo
    at = @task.due_at.in_time_zone(TZ)
    when_text = "#{WEEKDAYS_SHORT[at.wday]} #{at.strftime('%d/%m %H:%M')} · #{Crm::AgendaSlots::UNIT_LABELS[@task.unit] || @task.unit}"
    agent = AGENT_NAMES[@agent_key] || @agent_key
    return "#{patient_name} respondeu NÃO ao lembrete da consulta de #{when_text} — ligar para remarcar ou cancelar" if @kind == 'nao_confirmou'

    if @kind == 'agente_cancelou'
      "O #{agent} cancelou a consulta de #{patient_name} que era #{when_text}"
    else
      "O #{agent} remarcou a consulta de #{patient_name} para #{when_text}"
    end
  end
end
