class Api::V1::Accounts::Crm::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, only: [:show, :destroy, :send_now]

  def index
    campaigns = Current.account.crm_campaigns.order(created_at: :desc)
    render json: campaigns.map { |c| campaign_json(c) }
  end

  def show
    render json: campaign_json(@campaign)
  end

  def create
    @campaign = Current.account.crm_campaigns.create!(
      campaign_params.merge(sender: Current.user, status: :draft)
    )
    render json: campaign_json(@campaign), status: :created
  end

  def destroy
    return render_could_not_create_error('Campanha em processamento não pode ser excluída') if @campaign.processing?

    @campaign.destroy!
    head :no_content
  end

  def send_now
    return render_could_not_create_error('Campanha já foi enviada') unless @campaign.draft?

    @campaign.update!(status: :processing)
    Crm::CampaignRunJob.perform_later(@campaign.id)
    render json: campaign_json(@campaign)
  end

  # POST preview_audience — recebe o audience e devolve contagem + amostra
  def preview_audience
    preview = Crm::Campaign.new(account: Current.account, audience: audience_params)
    contacts = preview.resolve_audience
    render json: {
      count: contacts.size,
      sample: contacts.limit(10).map { |c| { id: c.id, name: c.name, phone_number: c.phone_number } }
    }
  end

  # GET templates?inbox_id= — templates aprovados do canal WhatsApp
  def templates
    inbox = Current.account.inboxes.find(params[:inbox_id])
    return render json: [] unless inbox.channel_type == 'Channel::Whatsapp'

    approved = (inbox.channel.message_templates || []).select do |t|
      t['status']&.downcase == 'approved'
    end
    render json: approved
  end

  private

  def campaign
    @campaign ||= Current.account.crm_campaigns.find(params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(
      :name, :inbox_id, :apply_label, :message_preview,
      template_params: {}, audience: {}
    )
  end

  def audience_params
    params.require(:audience).permit(
      include_label_ids: [], include_stage_ids: [],
      exclude_label_ids: [], exclude_stage_ids: []
    ).to_h
  end

  def campaign_json(c)
    {
      id: c.id,
      name: c.name,
      inbox_id: c.inbox_id,
      inbox_name: c.inbox&.name,
      template_params: c.template_params,
      message_preview: c.message_preview,
      audience: c.audience,
      apply_label: c.apply_label,
      status: c.status,
      stats: c.stats,
      sender_name: c.sender&.name,
      started_at: c.started_at,
      finished_at: c.finished_at,
      created_at: c.created_at
    }
  end
end
