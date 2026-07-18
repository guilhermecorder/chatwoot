class Api::V1::Accounts::Crm::MessageAutomationsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  before_action -> { require_capability(:campaigns) }, only: %i[create update destroy]
  before_action :automation, only: [:update, :destroy, :preview_eligible]

  def index
    automations = Current.account.crm_message_automations.order(created_at: :desc)
    render json: automations.map { |a| automation_json(a) }
  end

  def create
    @automation = Current.account.crm_message_automations.create!(
      automation_params.merge(sender: Current.user)
    )
    render json: automation_json(@automation), status: :created
  end

  def update
    @automation.update!(automation_params)
    render json: automation_json(@automation)
  end

  def destroy
    @automation.destroy!
    head :no_content
  end

  # GET preview_eligible — quantos contatos receberiam agora
  def preview_eligible
    contacts = @automation.eligible_contacts
    render json: {
      count: contacts.size,
      sample: contacts.limit(10).map { |c| { id: c.id, name: c.name, phone_number: c.phone_number } }
    }
  end

  private

  def automation
    @automation ||= Current.account.crm_message_automations.find(params[:id])
  end

  def automation_params
    params.require(:automation).permit(
      :name, :inbox_id, :trigger_label, :trigger_stage_id, :delay_days, :marker_label,
      :message_preview, :active,
      template_params: {}, required_labels: [], exclude_labels: []
    )
  end

  def automation_json(a)
    {
      id: a.id,
      name: a.name,
      inbox_id: a.inbox_id,
      inbox_name: a.inbox&.name,
      trigger_label: a.trigger_label,
      trigger_stage_id: a.trigger_stage_id,
      trigger_stage_name: a.trigger_stage&.name,
      delay_days: a.delay_days,
      required_labels: a.required_labels,
      exclude_labels: a.exclude_labels,
      marker_label: a.marker_label,
      template_params: a.template_params,
      message_preview: a.message_preview,
      active: a.active,
      stats: a.stats,
      created_at: a.created_at
    }
  end
end
