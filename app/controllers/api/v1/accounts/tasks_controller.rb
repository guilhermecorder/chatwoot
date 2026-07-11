class Api::V1::Accounts::TasksController < Api::V1::Accounts::BaseController
  before_action :task, only: [:update, :destroy]

  def index
    tasks = Current.account.tasks.includes(:creator, :assignee)
    tasks = tasks.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
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
    task.update!(task_params)
    render json: task_json(task)
  end

  def destroy
    task.destroy!
    head :no_content
  end

  private

  def task
    @task ||= Current.account.tasks.find(params[:id])
  end

  def task_params
    params.permit(:title, :description, :task_type, :priority, :status, :due_at, :assignee_id)
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
      creator: { id: t.creator.id, name: t.creator.name },
      assignee: t.assignee ? { id: t.assignee.id, name: t.assignee.name } : nil
    }
  end
end
