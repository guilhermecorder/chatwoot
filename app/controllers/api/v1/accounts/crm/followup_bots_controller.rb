class Api::V1::Accounts::Crm::FollowupBotsController < Api::V1::Accounts::BaseController
  # toggle é a CHAVE DE EMERGÊNCIA: qualquer atendente pode pausar/religar
  # um robô que estiver se comportando mal (gerenciar continua admin-only)
  before_action :check_admin, except: [:toggle]
  before_action :bot, only: [:update, :destroy, :toggle]

  def index
    bots = Current.account.crm_followup_bots.includes(:inbox, :sender).order(created_at: :desc)
    bots = bots.where(stage_id: params[:stage_id]) if params[:stage_id].present?
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

  private

  def bot
    @bot ||= Current.account.crm_followup_bots.find(params[:id])
  end

  def check_admin
    return if Current.account_user.administrator?

    render json: { error: 'Apenas administradores podem gerenciar robôs.' }, status: :forbidden
  end

  def bot_params
    params.require(:followup_bot).permit(
      :name, :inbox_id, :pipeline_id, :stage_id, :active, :starts_at, :ends_at,
      steps: [:delay_hours, :delay_value, :delay_unit, :kind, :message, { template_params: {} }],
      required_labels: [], exclude_labels: []
    )
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
      starts_at: b.starts_at,
      ends_at: b.ends_at,
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
