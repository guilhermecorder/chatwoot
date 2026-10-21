# 🩺 TAREFA DE PASSAGEM (item 251, 26/09): quando um atendente de IA precisa
# que uma PESSOA assuma (dúvida do caso, sintoma de alerta, documento, pedido
# para falar com alguém), abre uma tarefa no Meu Painel de quem cuida — não é
# consulta nem cirurgia (esses tipos ficam fora da lista "tarefas esperando
# você"), é uma tarefa comum do tipo `pos_op`.
#
# Quem recebe, nesta ordem: a pessoa escolhida no card do agente
# (task_assignee_id) → quem cuida da coluna do paciente (Crm::TaskOwner) →
# responsável pela conferência de cirurgia → o primeiro administrador da
# conta (auditoria 10/2026, #443: tarefa urgente nunca fica sem dono).
# Uma tarefa ABERTA por paciente: chamada nova só complementa a descrição.
# 🙋 #458: vale para os três atendentes do WhatsApp (não só o pós-operatório).
# 🔁 item 343 (13/10): paciente de RETORNO (a próxima consulta dele é retorno)
# ou card do agente com "Equipe dos retornos" → a tarefa nasce SEM dono
# individual, carimbada para a equipe (as duas veem; quem pegar assume).
# Fora do pós-operatório, o plano B é o responsável da conferência de
# CONSULTA (antes caía no de cirurgia para todo mundo).
class Crm::HandoffTask
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  TASK_TYPE = 'pos_op'.freeze
  # 🔁 343: nome com que os lembretes recusados abrem a tarefa
  CONFIRMATION_KEY = 'Confirmação de consulta'.freeze

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

  # aviso no Radar do Meu Painel: 'atendimento_atencao' para os Atendentes de
  # Agendamento / Pós-agendamento (#458); pós-operatório e ligação (item 333)
  # seguem com 'pos_op_atencao', como já estava
  WHATSAPP_ATTENTION_KEYS = %w[atendente_agendamento atendente_pos].freeze
  def alert!(task)
    kind = WHATSAPP_ATTENTION_KEYS.include?(@agent_key) ? 'atendimento_atencao' : 'pos_op_atencao'
    Crm::AgentAlert.push(account: @account, kind: kind, task: task, conversation: @conversation, agent_key: @agent_key)
  end

  def create!(motivo, detalhes, urgent)
    @account.tasks.create!(
      title: "#{urgent ? '🔴' : title_icon} #{title_label} · #{patient_name} — #{motivo}",
      description: entry(motivo, detalhes),
      task_type: TASK_TYPE, priority: urgent ? :urgent : :high, status: :todo,
      due_at: urgent ? TZ.now : TZ.now.end_of_day,
      contact: @contact, phone: @contact&.phone_number,
      creator: @account.administrators.first || @account.users.first,
      assignee: assignee,
      modality: team_task? ? Crm::TaskOwner::RETORNO : nil # 🔁 343: carimbo da equipe dos retornos
    )
  end

  # item 333: a tarefa aberta pelo Agente de Ligação diz que veio da ligação;
  # #458: a dos Atendentes de Agendamento/Pós-agendamento diz "Atendimento"
  TITLE_LABELS = { 'voice' => 'Ligação', 'atendente_pos_op' => 'Pós-op' }.freeze
  TITLE_ICONS = { 'voice' => '📞', 'atendente_pos_op' => '🩺' }.freeze
  def title_label = TITLE_LABELS[@agent_key] || 'Atendimento'
  def title_icon = TITLE_ICONS[@agent_key] || '🙋'

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
    return nil if team_task?

    chosen = @account.users.find_by(id: agent_cfg['task_assignee_id'].to_i) if agent_cfg['task_assignee_id'].to_i.positive?
    chosen || Crm::TaskOwner.resolve(@account, contact: @contact, task_type: owner_task_type) || fallback_admin
  end

  # 🔁 343: o pós-operatório (e a pesquisa NPS, que abre em nome dele) segue
  # com o responsável de cirurgia; os demais são de consulta
  def owner_task_type
    @agent_key == 'atendente_pos_op' ? 'cirurgia' : 'consulta'
  end

  # 🔁 343: o card do agente — a Confirmação de consulta guarda o seu na
  # configuração da Agenda (agenda_config.appointment_confirmation)
  def agent_cfg
    @agent_cfg ||= begin
      settings = CrmSetting.find_by(account: @account)
      cfg = if @agent_key == CONFIRMATION_KEY
              settings&.agenda_config&.dig('appointment_confirmation')
            else
              settings&.ai_config&.dig('agents', @agent_key)
            end
      cfg.is_a?(Hash) ? cfg : {}
    end
  end

  # 🔁 343: tarefa da EQUIPE DOS RETORNOS (sem dono individual)? Só com a
  # equipe configurada: o card do agente escolheu a equipe, ou o paciente
  # está em retorno (fora do pós-operatório — lá o caso é cirúrgico)
  def team_task?
    return @team_task if defined?(@team_task)

    @team_task = Crm::TaskOwner.retorno_team?(@account) &&
                 (agent_cfg['task_assignee_id'].to_s == Crm::TaskOwner::TEAM_CHOICE ||
                  (@agent_key != 'atendente_pos_op' && Crm::TaskOwner.patient_retorno?(@account, @contact)))
  end

  # #443: sem ninguém configurado, a tarefa vai para um administrador da conta
  # — de preferência um que ATENDE esta caixa (é membro dela); senão o
  # primeiro da conta. Nunca "a equipe (sem responsável definido)" num caso urgente.
  def fallback_admin
    admins = @account.administrators.order(:id)
    inbox_id = @conversation.try(:inbox_id)
    (inbox_id && admins.joins(:inbox_members).where(inbox_members: { inbox_id: inbox_id }).first) || admins.first
  end

  def patient_name
    @contact&.name.to_s.strip.presence || 'Paciente'
  end

  def agent_name
    Crm::ResponderTools::AGENT_NAMES[@agent_key] || @agent_key
  end

  def note!(task, motivo, urgent, created:)
    who = task.assignee&.name.presence ||
          (task.modality == Crm::TaskOwner::RETORNO ? 'a equipe dos retornos' : 'a equipe (sem responsável definido)')
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
