class Api::V1::Accounts::Crm::AutomationsController < Api::V1::Accounts::BaseController
  before_action :pipeline
  before_action :stage
  before_action :automation, only: [:update, :destroy, :trigger]

  def index
    items = @stage.automations.order(:created_at).map { |a| automation_json(a) }
    items += message_automation_items
    render json: items
  end

  def create
    @automation = @stage.automations.create!(automation_params)
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

  # Disparo manual para testes
  def trigger
    contact_id = params[:contact_id].to_i
    CrmAutomationFireJob.perform_later(@automation.id, contact_id, {})
    render json: { status: 'queued' }
  end

  private

  def pipeline
    @pipeline ||= Current.account.crm_pipelines.find(params[:pipeline_id])
  end

  def stage
    @stage ||= @pipeline.stages.find(params[:stage_id])
  end

  def automation
    @automation ||= @stage.automations.find(params[:id])
  end

  def automation_params
    params.require(:automation).permit(
      :name, :trigger_type, :delay_minutes, :action_type, :active,
      action_config: {}
    )
  end

  # Réguas de mensagem (Campanha WhatsApp) desta coluna aparecem no modo
  # programação como itens somente leitura — gerenciadas na central
  def message_automation_items
    Crm::MessageAutomation.where(account_id: Current.account.id, trigger_stage_id: @stage.id)
                          .order(:created_at).map do |a|
      {
        id: a.id,
        kind: 'message_automation',
        stage_id: @stage.id,
        name: a.name,
        trigger_type: 'card_stalled',
        delay_minutes: a.delay_days * 24 * 60,
        action_type: 'template_message',
        action_config: { 'template' => a.template_params['name'] },
        active: a.active,
        created_at: a.created_at
      }
    end
  end

  def automation_json(a)
    {
      id:            a.id,
      stage_id:      a.stage_id,
      name:          a.name,
      trigger_type:  a.trigger_type,
      delay_minutes: a.delay_minutes,
      action_type:   a.action_type,
      action_config: a.action_config,
      active:        a.active,
      created_at:    a.created_at
    }
  end
end
