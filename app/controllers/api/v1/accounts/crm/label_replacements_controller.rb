class Api::V1::Accounts::Crm::LabelReplacementsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  before_action -> { require_capability(:data_tools) }

  def preview
    return render_could_not_create_error('Informe as etiquetas') if params[:from].blank? || params[:to].blank?

    render json: Crm::LabelReplaceService.new(
      account: Current.account, from_label: params[:from], to_label: params[:to]
    ).preview
  end

  def apply
    return render_could_not_create_error('Informe as etiquetas') if params[:from].blank? || params[:to].blank?
    return render_could_not_create_error('As etiquetas são iguais') if params[:from] == params[:to]

    Crm::LabelReplaceJob.perform_later(Current.account.id, params[:from].to_s, params[:to].to_s)
    render json: { status: 'queued' }
  end
end
