class Api::V1::Accounts::Crm::LabelRemovalsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  before_action -> { require_capability(:data_tools) }

  def preview
    return render_could_not_create_error('Informe a etiqueta') if params[:label].blank?

    render json: Crm::LabelRemoveService.new(
      account: Current.account, label: params[:label], stage_id: params[:stage_id].presence
    ).preview
  end

  def apply
    return render_could_not_create_error('Informe a etiqueta') if params[:label].blank?

    Crm::LabelRemoveJob.perform_later(Current.account.id, params[:label].to_s, params[:stage_id].presence)
    render json: { status: 'queued' }
  end
end
