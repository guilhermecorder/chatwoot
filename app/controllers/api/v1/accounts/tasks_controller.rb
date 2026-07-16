class Api::V1::Accounts::TasksController < Api::V1::Accounts::BaseController
  before_action :task, only: [:update, :destroy]

  def index
    tasks = Current.account.tasks.includes(:creator, :assignee)

    # Privacidade: agente comum só vê as próprias tarefas (criadas por/para ele)
    # e as das UNIDADES (agenda compartilhada). Admin vê tudo.
    unless Current.account_user.administrator?
      uid = Current.user.id
      tasks = tasks.where('assignee_id = :uid OR creator_id = :uid OR unit IS NOT NULL', uid: uid)
    end

    tasks = tasks.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    tasks = tasks.where(unit: params[:unit]) if params[:unit].present?
    tasks = tasks.order(Arel.sql('priority DESC, due_at ASC NULLS LAST, created_at DESC'))
    render json: tasks.map { |t| task_json(t) }
  end

  def create
    new_task = Current.account.tasks.create!(
      task_params.merge(
        creator: Current.user,
        assignee_id: params[:assignee_id].presence || Current.user.id
      )
    )
    render json: task_json(new_task), status: :created
  end

  def update
    # consulta com dia/horário alterado = reagendamento (indicador do painel)
    if task.task_type == 'consulta' && params[:due_at].present? && task.due_at.present? &&
       Time.zone.parse(params[:due_at].to_s) != task.due_at
      task.rescheduled_count += 1
    end
    # cancelar/reativar consulta
    task.canceled_at = params[:canceled] ? Time.current : nil if params.key?(:canceled)

    # conferência do dia: compareceu = consulta concluída
    params[:status] = 'done' if params[:attendance] == 'attended' && params[:status].blank?

    task.update!(task_params)

    # comparecimento/indicação refletem no CRM (move o card + automações)
    reflect_attendance_in_crm if task.saved_change_to_attendance? || task.saved_change_to_surgery_indication?

    render json: task_json(task)
  end

  def destroy
    task.destroy!
    head :no_content
  end

  # POST /tasks/:id/comment — solicitação/ajuda entre quem criou e quem executa
  def comment
    return render json: { error: 'Sem acesso a esta tarefa.' }, status: :forbidden unless can_comment?

    text = params[:text].to_s.strip
    return render json: { error: 'Escreva a mensagem.' }, status: :unprocessable_entity if text.blank?

    entry = {
      'user_id' => Current.user.id,
      'name' => Current.user.name,
      'text' => text.first(600),
      'at' => Time.current.iso8601
    }
    task.update!(comments: Array(task.comments) + [entry])
    render json: task_json(task)
  end

  private

  def task
    @task ||= Current.account.tasks.find(params[:id])
  end

  def can_comment?
    Current.account_user.administrator? ||
      [task.creator_id, task.assignee_id].include?(Current.user.id)
  end

  def task_params
    params.permit(:title, :description, :task_type, :priority, :status, :due_at, :assignee_id, :unit,
                  :phone, :procedure, :doctor, :modality, :attendance, :surgery_indication, :indicated_procedure,
                  :contact_id)
  end

  # Conferência do dia → CRM: compareceu/faltou/cirurgia indicada movem o
  # card do contato (lógica compartilhada com a conduta do médico na
  # Central do Paciente — Crm::AttendanceReflector).
  def reflect_attendance_in_crm
    Crm::AttendanceReflector.call(account: Current.account, task: task)
  end

  # contato unificado (Fase 0) primeiro; telefone só para registro antigo sem link
  def patient_contact(task)
    task.contact || Task.match_contact(Current.account, task.phone)
  end

  def task_json(t)
    {
      id: t.id,
      title: t.title,
      description: t.description,
      task_type: t.task_type,
      priority: t.priority,
      status: t.status,
      due_at: t.due_at,
      completed_at: t.completed_at,
      created_at: t.created_at,
      unit: t.unit,
      phone: t.phone,
      contact_id: t.contact_id,
      procedure: t.procedure,
      doctor: t.doctor,
      modality: t.modality,
      canceled_at: t.canceled_at,
      rescheduled_count: t.rescheduled_count,
      attendance: t.attendance,
      surgery_indication: t.surgery_indication,
      indicated_procedure: t.indicated_procedure,
      comments: Array(t.comments),
      creator: { id: t.creator.id, name: t.creator.name },
      assignee: t.assignee ? { id: t.assignee.id, name: t.assignee.name } : nil
    }.merge(surgery_value_json(t))
  end

  # 💰 valor da cirurgia (SÓ ADMIN): valor do card no CRM + forma de
  # pagamento captada pelo agente de Fechamento (contact.surgery_closing)
  def surgery_value_json(t)
    return {} unless t.task_type == 'cirurgia' && Current.account_user.administrator?

    contact = patient_contact(t)
    return {} if contact.blank?

    card = Crm::Contact.joins(:pipeline)
                       .where(crm_pipelines: { account_id: Current.account.id }, contact_id: contact.id)
                       .order('crm_pipelines.position').first
    closing = contact.additional_attributes&.dig('surgery_closing') || {}
    {
      crm_value: closing['value'].presence || card&.value,
      surgery_payment: closing['payment']
    }
  rescue StandardError
    {}
  end
end
