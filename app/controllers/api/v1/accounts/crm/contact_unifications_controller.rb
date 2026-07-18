class Api::V1::Accounts::Crm::ContactUnificationsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:data_tools) }

  # POST /api/v1/accounts/:account_id/crm/contact_unification/preview
  def preview
    render json: Crm::ContactUnificationService.new(account: Current.account).preview
  end

  # POST /api/v1/accounts/:account_id/crm/contact_unification/apply
  # Roda em background (pode levar minutos com muitos contatos)
  def apply
    Crm::ContactUnificationJob.perform_later(Current.account.id)
    render json: { enqueued: true }
  end

  private

end
