class Api::V1::Accounts::Crm::FollowupBotsController < Api::V1::Accounts::BaseController
  # toggle é a CHAVE DE EMERGÊNCIA: qualquer atendente pode pausar/religar
  # um robô que estiver se comportando mal (gerenciar continua admin-only)
  include Crm::AccessControl

  before_action -> { require_capability(:automations) }, except: [:toggle]
  before_action :bot, only: [:update, :destroy, :toggle]

  def index
    bots = Current.account.crm_followup_bots.includes(:inbox, :sender).order(created_at: :desc)
    # robô da coluna (modo programação) + robô global que marcou esta coluna (item 315)
    bots = bots.where('stage_id = ? OR stage_ids @> ?', params[:stage_id].to_i, [params[:stage_id].to_i].to_json) if params[:stage_id].present?
    render json: bots.map { |b| bot_json(b) }
  end

  def create
    new_bot = Current.account.crm_followup_bots.create!(bot_params.merge(sender: Current.user))
    render json: bot_json(new_bot), status: :created
  end

  def update
    bot.update!(bot_params)
    render json: bot_json(bot)
  end

  def destroy
    bot.destroy!
    head :no_content
  end

  # POST /crm/followup_bots/:id/toggle — pausa/religa e registra QUEM mexeu
  # no registro de atividade (auditável no card do robô)
  def toggle
    bot.update!(active: !bot.active)

    log = bot.activity_log.presence || {}
    event = {
      'at' => Time.current.iso8601, 'type' => 'toggle',
      'note' => "#{bot.active ? '▶️ religado' : '⏸ pausado'} por #{Current.user.name}"
    }
    log['events'] = ([event] + Array(log['events'])).first(60)
    bot.update_columns(activity_log: log) # rubocop:disable Rails/SkipsModelValidations

    render json: bot_json(bot)
  end

  # item 315: exemplo da cutucada escrita pela IA para uma conversa real do
  # robô (a mais recente em silêncio nas caixas marcadas) — nada é enviado
  def ai_preview
    conversation = preview_conversation
    return render json: { error: 'Nenhuma conversa recente para servir de exemplo.' }, status: :unprocessable_entity if conversation.nil?

    result = Crm::FollowupAiNudgeService.new(conversation: conversation, step: preview_step).call
    return render json: { error: result[:error] }, status: :unprocessable_entity if result[:error]

    render json: { text: result[:text], reason: result[:reason], conversation_id: conversation.id,
                   contact_name: conversation.contact&.name, inbox_name: conversation.inbox&.name }
  end

  private

  def bot
    @bot ||= Current.account.crm_followup_bots.find(params[:id])
  end


  def bot_params
    permitted = params.require(:followup_bot).permit(
      :name, :inbox_id, :pipeline_id, :stage_id, :active, :starts_at, :ends_at,
      # item 315: kind 'ai' + orientação para a IA; caixas e colunas em que atua
      steps: [:delay_hours, :delay_value, :delay_unit, :delay_from, :kind, :message, :ai_instructions,
              { template_params: {}, skip_labels: [], only_labels: [] }],
      required_labels: [], exclude_labels: [], inbox_ids: [], stage_ids: []
    )
    if permitted.key?(:inbox_ids)
      permitted[:inbox_ids] = Array(permitted[:inbox_ids]).map(&:to_i) & Current.account.inboxes.pluck(:id)
      permitted[:inbox_id] = nil # as fichas substituem a caixa única antiga (senão ela segue valendo escondida)
    end
    permitted[:stage_ids] = Array(permitted[:stage_ids]).map(&:to_i) & account_stage_ids if permitted.key?(:stage_ids)
    permitted
  end

  def inbox_names
    @inbox_names ||= Current.account.inboxes.pluck(:id, :name).to_h
  end

  def account_stage_ids
    Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: Current.account.id }).pluck(:id)
  end

  # mesma seleção do robô (caixas marcadas + cerca dos parceiros do Oftalmofácil,
  # que nunca passam por IA), só em caixas de WhatsApp
  def preview_conversation
    inbox_ids = Array(params[:inbox_ids]).map(&:to_i) & Current.account.inboxes.pluck(:id)
    probe = Crm::FollowupBot.new(account: Current.account, inbox_ids: inbox_ids)
    scope = Crm::FollowupBotJob.new.candidates(probe).joins(:inbox).where(inboxes: { channel_type: 'Channel::Whatsapp' })
    scope = scope.where(id: params[:conversation_id]) if params[:conversation_id].present?
    scope.reorder(last_activity_at: :desc).first
  end

  def preview_step
    { 'kind' => 'ai', 'ai_instructions' => params[:ai_instructions].to_s[0, 1500],
      'delay_value' => params[:delay_value].presence || 24, 'delay_unit' => params[:delay_unit].presence || 'hours' }
  end

  def bot_json(b)
    {
      id: b.id,
      name: b.name,
      inbox_id: b.inbox_id,
      inbox_name: b.inbox&.name,
      pipeline_id: b.pipeline_id,
      stage_id: b.stage_id,
      active: b.active,
      steps: b.ordered_steps,
      required_labels: b.required_labels || [],
      exclude_labels: b.exclude_labels || [],
      inbox_ids: b.acting_inbox_ids, stage_ids: b.acting_stage_ids, # item 315
      inbox_names: inbox_names.values_at(*b.acting_inbox_ids).compact,
      starts_at: b.starts_at, ends_at: b.ends_at,
      created_at: b.created_at,
      last_run_at: b.last_run_at,
      window_status: window_status(b),
      activity: activity_json(b)
    }
  end

  # por que o robô pode estar parado — pra tela avisar em vez de falhar em silêncio
  def window_status(bot)
    return 'pausado' unless bot.active
    return 'janela_encerrada' if bot.ends_at.present? && Time.current > bot.ends_at
    return 'ainda_nao_comecou' if bot.starts_at.present? && Time.current < bot.starts_at

    'ok'
  end

  def activity_json(bot)
    log = bot.activity_log.presence || {}
    { last_run: log['last_run'], events: Array(log['events']).first(30) }
  end
end
