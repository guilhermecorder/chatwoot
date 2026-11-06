# 🎯 AGENTE DE CAMPANHAS (item 352, 19/10/2026): Análises → Campanhas.
# Lê Meta + Google em três níveis (campanha → conjunto → anúncio) com a
# jornada do CRM, a NOSSA MÉDIA de 7/30/90/180/360 dias, as recomendações do
# agente (sugerida → aprovada → aplicada → aprendizado), os parâmetros e as
# fichas de subir campanha. Nó marketing.campanhas: ver = lê; editar =
# aprova, aplica, muda parâmetros e sobe campanha.
class Api::V1::Accounts::Crm::CampaignAgentController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  before_action :set_action, only: [:decide, :apply, :manual]

  # GET /crm/campaign_agent?preset=last7&channel=meta|google
  def show # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    since, until_at = standard_period_range || default_range
    since_d = since.to_date
    until_d = until_at.to_date
    channels = params[:channel].presence_in(%w[meta google seo]) ? [params[:channel]] : %w[meta google]
    reader_obj = Cevico::CampaignAgent::Reader.new(account: account, since_date: since_d, until_date: until_d, goal: agent_params['goal'],
                                                   channels: channels)
    reader = reader_obj.call
    days = (until_d - since_d).to_i + 1
    previous = Cevico::CampaignAgent::Reader.new(account: account, since_date: since_d - days, until_date: since_d - 1,
                                                 goal: agent_params['goal'], channels: channels).totals
    render json: {
      period: { from: since_d.iso8601, to: until_d.iso8601, days: days, preset: params[:preset].presence || 'last7' },
      params: agent_params,
      goal_label: Cevico::CampaignAgent::Params.goal_label(agent_params),
      channels: channel_status,
      campaigns: reader[:campaigns],
      totals: reader[:totals],
      previous: previous,
      time_to_book: reader[:time_to_book],
      series: reader_obj.daily, # dia a dia para os gráficos (358c)
      baselines: Cevico::CampaignAgent::Baselines.new(account: account, goal: agent_params['goal']).call,
      actions: actions_json(channels),
      scoreboard: Cevico::CampaignAgent::Learning.scoreboard(account),
      state: Cevico::CampaignAgent::Daily.state(account),
      briefs: Cevico::CampaignAgent::Launcher.new(account: account).list,
      creatives: creatives_json,
      can_edit: cevico_can?('marketing.campanhas', :edit)
    }
  end

  # POST /crm/campaign_agent/params — os parâmetros do agente
  def update_params
    render json: { params: Cevico::CampaignAgent::Params.save!(account, params.require(:params)) }
  end

  # POST /crm/campaign_agent/decide { id, decision: approve | dismiss | reopen }
  def decide
    case params[:decision].to_s
    when 'approve'
      return bad('Esta recomendação não está esperando decisão.') unless @action.status == 'suggested'

      @action.update!(status: 'approved', decided_at: Time.current, decided_by_id: Current.user.id)
    when 'dismiss'
      return bad('Esta recomendação não está aberta.') unless @action.open?

      @action.update!(status: 'dismissed', decided_at: Time.current, decided_by_id: Current.user.id)
    when 'reopen'
      return bad('Só o que foi descartado ou expirou volta para a fila.') unless %w[dismissed expired].include?(@action.status)

      @action.update!(status: 'suggested', decided_at: nil, decided_by_id: nil)
    else
      return bad('Decisão desconhecida.')
    end
    render json: { action: @action.as_json, actions: actions_json }
  end

  # POST /crm/campaign_agent/apply { id } — aplica (API da Meta) ou devolve o passo a passo
  def apply
    result = executor.apply(@action)
    status = result[:ok] ? :ok : :unprocessable_entity
    render json: result.merge(action: @action.reload.as_json, actions: actions_json), status: status
  end

  # POST /crm/campaign_agent/manual { id } — "fiz à mão"
  def manual
    result = executor.mark_manual(@action)
    render json: result.merge(action: @action.reload.as_json, actions: actions_json), status: result[:ok] ? :ok : :unprocessable_entity
  end

  # POST /crm/campaign_agent/run — "Ler agora" (roda no Sidekiq)
  def run
    Crm::CampaignAgentJob.perform_later(account.id, force: true)
    render json: { queued: true }
  end

  # POST /crm/campaign_agent/brief — guarda a ficha e monta o plano
  def plan_brief
    result = Cevico::CampaignAgent::Launcher.new(account: account, params: agent_params, user: Current.user).plan!(params.require(:brief))
    render json: result.merge(briefs: Cevico::CampaignAgent::Launcher.new(account: account).list), status: result[:ok] ? :ok : :unprocessable_entity
  end

  # POST /crm/campaign_agent/launch { id } — cria PAUSADA na Meta
  def launch
    result = Cevico::CampaignAgent::Launcher.new(account: account, params: agent_params, user: Current.user).launch!(params[:id])
    render json: result.merge(briefs: Cevico::CampaignAgent::Launcher.new(account: account).list), status: result[:ok] ? :ok : :unprocessable_entity
  end

  # POST /crm/campaign_agent/remove_brief { id }
  def remove_brief
    render json: { briefs: Cevico::CampaignAgent::Launcher.new(account: account).remove!(params[:id]) }
  end

  private

  def account
    Current.account
  end

  def agent_params
    @agent_params ||= Cevico::CampaignAgent::Params.for(account)
  end

  def executor
    Cevico::CampaignAgent::Executor.new(account: account, params: agent_params, user: Current.user)
  end

  def set_action
    @action = Crm::CampaignAction.where(channel: %w[meta google pages]).find_by(account_id: account.id, id: params[:id])
    render json: { error: 'Recomendação não encontrada.' }, status: :not_found if @action.nil?
  end

  def bad(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def default_range
    now = PERIOD_TZ.now
    [(now - 6.days).beginning_of_day, now.end_of_day]
  end

  # abertas + as últimas 60 decididas (histórico e aprendizado)
  # item 359: no azulejo SEO / orgânico a fila é a do Agente de Páginas (canal pages)
  def actions_json(channels = %w[meta google])
    scope = (channels == %w[seo] ? Crm::CampaignAction.pages : Crm::CampaignAction.ads).where(account_id: account.id)
    { open: scope.open.recent.map(&:as_json),
      history: scope.where.not(status: Crm::CampaignAction::OPEN).order(updated_at: :desc).limit(60).map(&:as_json) }
  end

  def channel_status
    settings = CrmSetting.find_by(account: account)
    meta = settings&.meta_ads_config || {}
    settings&.google_ads_config || {}
    { meta: { configured: meta['access_token'].present? && meta['ad_account_id'].present?, sync: meta['creatives_sync'] || {},
              execute: agent_params['execute_api'] },
      google: { configured: Cevico::CampaignAgent::GoogleSync.new(account: account).configured?,
                sync: Cevico::CampaignAgent::GoogleSync.state(account) },
      seo: { configured: true, search_console: Cevico::SearchConsole.new(account).configured?,
             pages: CevicoPage.where(account_id: account.id).published.count } }
  end

  # criativos ativos da Central para reaproveitar na ficha de subida
  def creatives_json
    Crm::AdCreative.where(account_id: account.id).where.not(effective_status: %w[DELETED ARCHIVED UNKNOWN])
                   .order(synced_at: :desc).limit(60)
                   .map do |c|
      { ad_id: c.ad_id, name: c.ad_name, format: c.format, campaign_name: c.campaign_name,
        thumbnail: c.creative['thumbnail_url'] }
    end
  end
end
