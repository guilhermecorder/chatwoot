# 🔧 Um atendente de IA REMARCOU ou CANCELOU uma consulta pelo WhatsApp
# (rodada 192, ferramentas ao vivo) → aviso no Radar do Meu Painel, para a
# equipe conferir na Agenda. Entra na mesma lista dos avisos do Radar de
# Oportunidades (ai_config opportunity_state.alerts), kinds 'agente_remarcou'
# e 'agente_cancelou'; some sozinho após 24 h. Espelha Crm::Calls::RadarAlert.
# Direcionado à pessoa que cuida da consulta (task.assignee_id); sem
# responsável = todos veem. Retorno (item 343) = cada pessoa da equipe dos retornos.
class Crm::AgentAlert
  # item 217: 'nao_confirmou' = paciente respondeu NÃO ao lembrete da véspera
  # item 251: 'pos_op_atencao' = sintoma de alerta no pós-operatório (tarefa urgente aberta)
  # auditoria 10/2026 (#458): 'atendimento_atencao' = Atendente de Agendamento /
  # Pós-agendamento chamou a equipe (urgência, caso clínico, pedido fora do roteiro)
  # auditoria 10/2026 (#217): 'robo_parado' = um robô (cron) parou ou terminou
  # em erro 2× seguidas (Crm::CronWatchdogJob) — aviso para o administrador
  ROBOT_KIND = 'robo_parado'.freeze
  KINDS = (%w[agente_remarcou agente_cancelou nao_confirmou pos_op_atencao atendimento_atencao] + [ROBOT_KIND]).freeze
  ATTENTION_KINDS = %w[pos_op_atencao atendimento_atencao].freeze
  TTL = 24.hours
  MAX_ALERTS = 30
  TZ = Crm::AgendaSlots::TZ
  WEEKDAYS_SHORT = %w[dom seg ter qua qui sex sáb].freeze
  AGENT_NAMES = { 'atendente_agendamento' => 'Atendente de Agendamento', 'atendente_pos' => 'Atendente Pós-agendamento',
                  'atendente_pos_op' => 'Atendente de Pós-operatório', 'voice' => 'Agente de Ligação' }.freeze

  def self.push(account:, kind:, task:, conversation:, agent_key:)
    raise ArgumentError, "kind inválido: #{kind}" unless KINDS.include?(kind.to_s)

    new(account: account, kind: kind.to_s, task: task, conversation: conversation, agent_key: agent_key.to_s).push
  rescue StandardError => e
    Rails.logger.warn("[CEVICO agente] aviso do Radar não gravado: #{e.message}")
    nil
  end

  # o aviso continua valendo? (24 h, e a consulta ainda existe nesta conta;
  # o de robô parado vale enquanto o robô continuar com problema)
  def self.still_open?(account, alert)
    created = Time.zone.parse(alert['created_at'].to_s)
    return false if created.nil? || created < TTL.ago
    return robot_still_open?(alert) if alert['kind'] == ROBOT_KIND

    account.tasks.exists?(id: alert['task_id'])
  rescue ArgumentError
    false
  end

  # 🚨 #217: o robô (ou a fila 'sidekiq', que não está em CronHealth::JOBS)
  # continua com problema?
  def self.robot_still_open?(alert)
    return Crm::CronHealth.sidekiq_stalled?(Time.current) if alert['job'].to_s == 'sidekiq'

    Crm::CronHealth.problem_for(alert['job']).present?
  end

  # 🚨 #217: aviso de ROBÔ PARADO no Radar do Meu Painel, direcionado ao
  # administrador (não tem paciente nem consulta). Um aviso por robô: o novo
  # substitui o anterior. Fica fora do popup de prioridade (o popup é de
  # conversa com paciente — 'lock' => true, como a ligação travada): o
  # administrador já recebe a tarefa 🔴 e o e-mail.
  def self.push_robot(account:, problem:, user:, task: nil) # rubocop:disable Metrics/MethodLength
    alert = {
      'kind' => ROBOT_KIND, 'job' => problem[:job], 'task_id' => task&.id,
      'conversation_id' => nil, 'contact_id' => nil,
      'contact_name' => problem[:label],
      'stage_name' => problem[:kind] == 'erro' ? 'Robô com erro' : 'Robô parado',
      'motivo' => problem[:message],
      'acao' => 'Avisar quem cuida do sistema e, enquanto isso, conferir à mão o que esse robô faria hoje.',
      'user_id' => user&.id, 'user_name' => user&.name, 'lock' => true,
      'created_at' => Time.current.iso8601
    }
    Cevico::SettingMerge.merge_key!(account, :ai_config, 'opportunity_state') do |state|
      alerts = Array(state['alerts']).reject { |a| a['kind'] == ROBOT_KIND && a['job'] == problem[:job] }
      alerts << alert
      state['alerts'] = alerts.last(MAX_ALERTS)
      state
    end
    alert
  rescue StandardError => e
    Rails.logger.warn("[CEVICO saúde dos robôs] aviso do Radar não gravado: #{e.message}")
    nil
  end

  def initialize(account:, kind:, task:, conversation:, agent_key:)
    @account = account
    @kind = kind
    @task = task
    @conversation = conversation
    @agent_key = agent_key
  end

  # 🔒 Rodada 4 da auditoria (#102): pelo gravador único do crm_settings
  # (Cevico::SettingMerge) — mesma trava de linha de antes, agora no padrão da
  # casa; a chave continua opportunity_state.alerts (o Meu Painel lê dali)
  def push
    base = build
    news = recipients.map { |user_id, user_name| base.merge('user_id' => user_id, 'user_name' => user_name) }
    Cevico::SettingMerge.merge_key!(@account, :ai_config, 'opportunity_state') do |state|
      alerts = Array(state['alerts']).reject { |a| a['kind'] == @kind && a['task_id'] == @task.id }
      alerts.concat(news)
      state['alerts'] = alerts.last(MAX_ALERTS)
      state
    end
    news.first
  end

  private

  # 🔁 item 343 (13/10): aviso de RETORNO ("disse NÃO", remarcou, tarefa da
  # equipe) vai para CADA pessoa da equipe dos retornos — o popup e o Radar
  # filtram por user_id — e não para quem marcou a consulta. "Atender agora"
  # tira as cópias de todas de uma vez (sai pela conversa). Sem equipe
  # configurada (ou fora de retorno): o responsável da consulta, como antes.
  def recipients
    if Crm::TaskOwner.retorno?(@task)
      team = @account.users.where(id: Crm::TaskOwner.retorno_team_ids(@account)).order(:id).pluck(:id, :name)
      return team if team.any?
    end
    [[@task.assignee_id, @task.assignee&.name]]
  end

  def build
    contact = @task.contact || @conversation&.contact
    {
      'kind' => @kind, 'task_id' => @task.id,
      'conversation_id' => @conversation&.display_id,
      'contact_id' => contact&.id,
      'contact_name' => patient_name,
      # telefone da CONSULTA (pode ser de um familiar), não o do WhatsApp que pediu
      'phone' => @task.phone.presence || contact&.phone_number,
      'stage_name' => stage_name,
      'motivo' => motivo, 'acao' => acao,
      'user_id' => @task.assignee_id, 'user_name' => @task.assignee&.name,
      'created_at' => Time.current.iso8601
    }
  end

  def acao
    case @kind
    when 'nao_confirmou' then 'Ligar para o paciente'
    when *ATTENTION_KINDS then 'Falar com o paciente agora'
    else 'Conferir na Agenda'
    end
  end

  def patient_name
    return (@task.contact&.name.presence || 'Paciente') if ATTENTION_KINDS.include?(@kind)

    @task.title.to_s.sub(/\AConsulta:\s*/i, '').strip.presence || 'Paciente'
  end

  def stage_name
    case @kind
    when 'agente_cancelou' then 'Consulta cancelada'
    when 'nao_confirmou' then 'Não confirmou a consulta'
    when 'pos_op_atencao' then 'Pós-operatório: atenção'
    when 'atendimento_atencao' then 'Atendimento: a equipe precisa assumir'
    else 'Consulta remarcada'
    end
  end

  def motivo
    return "#{patient_name}: #{@task.title.to_s.split(' — ').last} — #{agent_label} pediu atenção" if ATTENTION_KINDS.include?(@kind)
    return nao_confirmou_motivo if @kind == 'nao_confirmou'

    if @kind == 'agente_cancelou'
      "O #{agent_label} cancelou a consulta de #{patient_name} que era #{when_text}"
    else
      "O #{agent_label} remarcou a consulta de #{patient_name} para #{when_text}"
    end
  end

  def nao_confirmou_motivo
    # item 333: o NÃO também pode vir da ligação com a assistente virtual
    return "#{patient_name} disse na ligação que NÃO vai à consulta de #{when_text} — ligar para remarcar ou cancelar" if @agent_key == 'voice'

    "#{patient_name} respondeu NÃO ao lembrete da consulta de #{when_text} — ligar para remarcar ou cancelar"
  end

  def agent_label
    AGENT_NAMES[@agent_key] || @agent_key
  end

  def when_text
    at = @task.due_at.in_time_zone(TZ)
    "#{WEEKDAYS_SHORT[at.wday]} #{at.strftime('%d/%m %H:%M')} · #{Crm::AgendaSlots::UNIT_LABELS[@task.unit] || @task.unit}"
  end
end
