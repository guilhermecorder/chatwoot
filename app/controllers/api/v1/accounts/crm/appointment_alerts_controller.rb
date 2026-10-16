# 🔔 ITEM 346 — NOTIFICAÇÕES SOBRE AGENDAMENTOS (ver Crm::AppointmentAlerts).
# Admin vê todos os alertas; o atendente vê os dele (responsável pelo card ou
# pela consulta). A trava de ver × editar vem do catálogo (nó agenda.notificacoes).
class Api::V1::Accounts::Crm::AppointmentAlertsController < Api::V1::Accounts::BaseController
  rescue_from ArgumentError, ActiveRecord::RecordInvalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def index
    render json: { payload: alerts.items }
  end

  def count
    render json: { count: alerts.count }
  end

  def merge
    kept = actions.merge!(keep_id: params.require(:keep_id), drop_id: params.require(:drop_id))
    render json: { ok: true, contact_id: kept.id }
  end

  def not_same
    actions.not_same!(one_id: params.require(:one_id), other_id: params.require(:other_id))
    render json: { ok: true }
  end

  def move_task
    task = actions.move_task!(task_id: params.require(:task_id), contact_id: params[:contact_id],
                              name: params[:name], phone: params[:phone])
    render json: { ok: true, contact_id: task.contact_id }
  end

  def rename
    actions.rename!(contact_id: params.require(:contact_id), name: params.require(:name))
    render json: { ok: true }
  end

  def reviewed
    actions.reviewed!(contact_id: params[:contact_id], type: params[:type], other_id: params[:other_id], task_id: params[:task_id])
    render json: { ok: true }
  end

  private

  def alerts
    Crm::AppointmentAlerts.new(account: Current.account, user: Current.user, admin: Current.account_user&.administrator?)
  end

  def actions
    Crm::AppointmentAlertActions.new(account: Current.account, user: Current.user)
  end
end
