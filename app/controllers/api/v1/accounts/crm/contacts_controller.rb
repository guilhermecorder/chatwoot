class Api::V1::Accounts::Crm::ContactsController < Api::V1::Accounts::BaseController
  before_action :pipeline
  before_action :crm_contact, only: [:update, :destroy, :history]

  def index
    crm_contacts = @pipeline.crm_contacts.includes(:contact, :stage, :assignee)
    render json: crm_contacts.map { |c| contact_json(c) }
  end

  def create
    contact = Current.account.contacts.find(params[:contact_id])
    stage = @pipeline.stages.find(params[:stage_id])
    @crm_contact = @pipeline.crm_contacts.create!(
      contact: contact,
      stage: stage,
      assignee_id: params[:assignee_id],
      value: params[:value],
      origin: params[:origin],
      procedure_of_interest: params[:procedure_of_interest],
      notes: params[:notes]
    )
    render json: contact_json(@crm_contact), status: :created
  end

  def update
    previous_stage = @crm_contact.stage
    @crm_contact.update!(crm_contact_params)

    # Dispara automações se o card mudou de coluna
    if @crm_contact.saved_change_to_stage_id?
      new_stage = @crm_contact.stage
      CrmAutomationTriggerService.new(
        crm_contact:    @crm_contact,
        new_stage:      new_stage,
        previous_stage: previous_stage,
        event_type:     'card_entered'
      ).call

      CrmAutomationTriggerService.new(
        crm_contact:    @crm_contact,
        new_stage:      previous_stage,
        previous_stage: previous_stage,
        event_type:     'card_left'
      ).call
    end

    render json: contact_json(@crm_contact)
  end

  def destroy
    @crm_contact.destroy!
    head :no_content
  end

  def history
    logs = @crm_contact.stage_logs.order(entered_at: :asc)
    render json: logs.map { |log|
      {
        id:               log.id,
        stage_id:         log.stage_id,
        stage_name:       log.stage_name,
        stage_color:      log.stage_color,
        event_type:       log.event_type,
        entered_at:       log.entered_at,
        left_at:          log.left_at,
        duration_minutes: log.duration_minutes,
      }
    }
  end

  # POST /crm/pipelines/:pipeline_id/contacts/:id/trigger_label_change
  # Chamado pelo frontend após salvar etiquetas — recebe diff e dispara automações
  def trigger_label_change
    added   = Array(params[:added])
    removed = Array(params[:removed])

    added.each do |label|
      CrmAutomationTriggerService.new(
        crm_contact:    @crm_contact,
        new_stage:      @crm_contact.stage,
        previous_stage: @crm_contact.stage,
        event_type:     'label_added',
        label:          label
      ).call
    end

    removed.each do |label|
      CrmAutomationTriggerService.new(
        crm_contact:    @crm_contact,
        new_stage:      @crm_contact.stage,
        previous_stage: @crm_contact.stage,
        event_type:     'label_removed',
        label:          label
      ).call
    end

    head :ok
  end

  private

  def pipeline
    @pipeline ||= Current.account.crm_pipelines.find(params[:pipeline_id])
  end

  def crm_contact
    @crm_contact ||= @pipeline.crm_contacts.find(params[:id])
  end

  def crm_contact_params
    params.permit(:stage_id, :assignee_id, :value, :origin, :procedure_of_interest, :notes)
  end

  def contact_json(c)
    contact = c.contact
    last_conversation = contact.conversations.includes(:inbox).order(last_activity_at: :desc).first
    last_conv_data = build_conversation_data(last_conversation)

    {
      id: c.id,
      contact_id: contact.id,
      name: contact.name,
      phone_number: contact.phone_number,
      email: contact.email,
      avatar_url: contact.avatar_url,
      contact_created_at: contact.created_at,
      crm_created_at: c.created_at,
      stage_id: c.stage_id,
      pipeline_id: c.pipeline_id,
      assignee: c.assignee ? { id: c.assignee.id, name: c.assignee.name } : nil,
      value: c.value,
      origin: c.origin,
      procedure_of_interest: c.procedure_of_interest,
      notes: c.notes,
      labels: contact.label_list,
      last_activity_at: contact.last_activity_at,
      conversations_count: contact.conversations.count,
      last_conversation_id: last_conversation&.id,
      last_conversation: last_conv_data,
    }
  end

  def build_conversation_data(conversation)
    return nil unless conversation

    last_msg = conversation.messages
                           .where.not(message_type: 2)
                           .order(created_at: :desc)
                           .first

    {
      id: conversation.id,
      status: conversation.status,
      inbox_name: conversation.inbox&.name,
      channel_type: conversation.inbox&.channel_type,
      last_message: last_msg&.content&.slice(0, 120),
      last_message_at: last_msg&.created_at,
    }
  end
end
