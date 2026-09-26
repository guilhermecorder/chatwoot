# 🩺 TAREFA DE PASSAGEM (item 251, 26/09): quando um atendente de IA precisa
# que uma PESSOA assuma (dúvida do caso, sintoma de alerta, documento, pedido
# para falar com alguém), abre uma tarefa no Meu Painel de quem cuida — não é
# consulta nem cirurgia (esses tipos ficam fora da lista "tarefas esperando
# você"), é uma tarefa comum do tipo `pos_op`.
#
# Quem recebe, nesta ordem: a pessoa escolhida no card do agente
# (task_assignee_id) → quem cuida da coluna do paciente (Crm::TaskOwner) →
# responsável pela conferência de cirurgia → ninguém (fica visível ao admin).
# Uma tarefa ABERTA por paciente: chamada nova só complementa a descrição.
class Crm::HandoffTask
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  TASK_TYPE = 'pos_op'.freeze

  def self.open!(account:, contact:, conversation:, agent_key:, motivo:, detalhes: nil, urgencia: 'normal') # rubocop:disable Metrics/ParameterLists
    new(account: account, contact: contact, conversation: conversation, agent_key: agent_key).open!(motivo, detalhes, urgencia)
  end

  def initialize(account:, contact:, conversation:, agent_key:)
    @account = account
    @contact = contact
    @conversation = conversation
    @agent_key = agent_key.to_s
  end

  # devolve { task:, created: true/false }
  def open!(motivo, detalhes, urgencia)
    motivo = motivo.to_s.strip.first(120).presence || 'Paciente precisa de atenção da equipe'
    urgent = urgencia.to_s == 'alta'
    existing = open_task
    return append!(existing, motivo, detalhes, urgent) if existing

    task = create!(motivo, detalhes, urgent)
    note!(task, motivo, urgent, created: true)
    alert!(task) if urgent
    { task: task, created: true }
  end

  private

  def append!(existing, motivo, detalhes, urgent)
    existing.update!(description: [existing.description.presence, entry(motivo, detalhes)].compact.join("\n\n"),
                     priority: urgent ? :urgent : existing.priority)
    note!(existing, motivo, urgent, created: false)
    alert!(existing) if urgent
    { task: existing, created: false }
  end

  def alert!(task)
    Crm::AgentAlert.push(account: @account, kind: 'pos_op_atencao', task: task, conversation: @conversation, agent_key: @agent_key)
  end

  def create!(motivo, detalhes, urgent)
    @account.tasks.create!(
      title: "#{urgent ? '🔴' : '🩺'} Pós-op · #{patient_name} — #{motivo}",
      description: entry(motivo, detalhes),
      task_type: TASK_TYPE, priority: urgent ? :urgent : :high, status: :todo,
      due_at: urgent ? TZ.now : TZ.now.end_of_day,
      contact: @contact, phone: @contact&.phone_number,
      creator: @account.administrators.first || @account.users.first,
      assignee: assignee
    )
  end

  def open_task
    return nil if @contact.blank?

    @account.tasks.where(contact_id: @contact.id, task_type: TASK_TYPE, status: %i[todo doing]).order(:created_at).first
  end

  def entry(motivo, detalhes)
    lines = ["#{TZ.now.strftime('%d/%m %H:%M')} · #{agent_name}: #{motivo}"]
    lines << detalhes.to_s.strip.first(1500) if detalhes.present?
    lines << "Conversa ##{@conversation.display_id}" if @conversation.respond_to?(:display_id)
    lines.join("\n")
  end

  def assignee
    cfg = CrmSetting.find_by(account: @account)&.ai_config&.dig('agents', @agent_key) || {}
    chosen = @account.users.find_by(id: cfg['task_assignee_id'].to_i) if cfg['task_assignee_id'].to_i.positive?
    chosen || Crm::TaskOwner.resolve(@account, contact: @contact, task_type: 'cirurgia')
  end

  def patient_name
    @contact&.name.to_s.strip.presence || 'Paciente'
  end

  def agent_name
    Crm::ResponderTools::AGENT_NAMES[@agent_key] || @agent_key
  end

  def note!(task, motivo, urgent, created:)
    who = task.assignee&.name.presence || 'a equipe (sem responsável definido)'
    verb = created ? 'abriu a tarefa' : 'complementou a tarefa aberta'
    @conversation.messages.create!(
      account_id: @account.id, inbox_id: @conversation.inbox_id, message_type: :activity, private: true,
      content: "#{urgent ? '🔴' : '🩺'} #{agent_name} #{verb} ##{task.id} para #{who}: #{motivo}. " \
               "[Ver tarefas](/app/accounts/#{@account.id}/tasks)"
    )
  rescue StandardError => e
    Rails.logger.warn "[Crm::HandoffTask] nota: #{e.message}"
  end
end
