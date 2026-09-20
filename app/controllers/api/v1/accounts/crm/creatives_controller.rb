# Central de Criativos (item 172): desempenho individual dos anúncios da Meta
# lido como gancho / corpo / CTA, cruzado com a jornada do CRM.
class Api::V1::Accounts::Crm::CreativesController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod
  before_action -> { require_capability(:reports) }

  RUNNING_STALE = 30.minutes

  # GET /crm/creatives?preset=month[&campaign_id=&fmt=&status=&q=&sort=]
  # (fmt, não format: params[:format] é o formato da requisição nas rotas da API)
  def index
    render json: analytics.overview(
      campaign_id: params[:campaign_id].presence, format: params[:fmt].presence,
      status: params[:status].presence, query: params[:q].presence, sort: params[:sort].presence || 'spend'
    ).merge(base_json)
  end

  # GET /crm/creatives/:ad_id
  def show
    render json: analytics.detail(params[:ad_id]).merge(base_json)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'anúncio não encontrado' }, status: :not_found
  end

  # GET /crm/creatives/history — recordes (dia/semana/mês), campeões por mês e de todos os tempos
  def history
    records = Crm::CreativeRecords.new(account: Current.account).call
    render json: records.merge(assets_months: analytics.assets_history(months: params[:months].to_i.clamp(1, 12).then { |m| m.zero? ? 6 : m }),
                               targets: Crm::CreativeTargets.for(Current.account))
  end

  # GET /crm/creatives/assets — ranking de ganchos, corpos e CTAs (criativo dinâmico)
  def assets
    render json: analytics.assets_for(nil).merge(base_json)
  end

  # POST /crm/creatives/sync[?days=30] — atualiza agora (fila low, trava por conta)
  def sync
    return render json: { error: 'Meta Ads não configurado (token e conta de anúncios).' }, status: :unprocessable_entity unless graph.configured?
    return render json: { error: 'Atualização já em andamento.', sync: sync_state }, status: :conflict if running?
    return render json: { error: 'Aguarde alguns minutos entre atualizações.', sync: sync_state }, status: :too_many_requests if too_soon?

    days = params[:days].to_i.clamp(0, Crm::AdInsightsSyncService::MAX_DAYS)
    Crm::AdInsightsSyncJob.perform_later(Current.account.id, days.positive? ? days : nil)
    render json: { enqueued: true, sync: sync_state }
  end

  # POST /crm/creatives/load_history — carga COMPLETA (até 37 meses, em janelas),
  # só admin; roda em segundo plano e o progresso aparece em sync_status
  def load_history
    return render json: { error: 'Só administrador carrega o histórico completo.' }, status: :forbidden unless Current.account_user&.administrator?
    return render json: { error: 'Meta Ads não configurado (token e conta de anúncios).' }, status: :unprocessable_entity unless graph.configured?
    return render json: { error: 'Atualização já em andamento.', sync: sync_state }, status: :conflict if running?

    Crm::AdInsightsSyncJob.perform_later(Current.account.id, Crm::AdInsightsSyncService::MAX_DAYS)
    render json: { enqueued: true, days: Crm::AdInsightsSyncService::MAX_DAYS, sync: sync_state }
  end

  # item 181: todos os vídeos pendentes; :ad_id/transcribe = um só
  def transcribe_videos
    count = Crm::AdVideoTranscribeJob.enqueue_pending(Current.account, limit: 100)
    render json: { enqueued: count }
  end

  def transcribe
    creative = Crm::AdCreative.find_by!(account_id: Current.account.id, ad_id: params[:ad_id].to_s)
    return render json: { error: 'Só anúncios em vídeo têm transcrição.' }, status: :unprocessable_entity unless creative.video?

    creative.queue_transcript!
    Crm::AdVideoTranscribeJob.perform_later(creative.id)
    render json: { enqueued: true, transcript: creative.transcript }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'anúncio não encontrado' }, status: :not_found
  end

  def sync_status
    render json: { sync: sync_state, configured: graph.configured?, storage: storage_summary }
  end

  # GET /crm/creatives/export[?preset=|from=&to=] — CSV do que está guardado aqui
  def export
    range = params[:all].present? ? [nil, nil] : [since_date, until_date]
    exporter = Crm::CreativesExport.new(account: Current.account, since_date: range.first, until_date: range.last)
    send_data exporter.call, filename: exporter.filename, type: 'text/csv; charset=utf-8'
  end

  private

  def analytics
    @analytics ||= Crm::CreativeAnalyticsService.new(account: Current.account, since_date: since_date, until_date: until_date)
  end

  def graph
    @graph ||= Crm::MetaGraph.new(account: Current.account)
  end

  def base_json
    { configured: graph.configured?, simulated: graph.simulate?, ad_account_id: graph.ad_account_id,
      since: since_date, until: until_date, sync: sync_state, targets: Crm::CreativeTargets.for(Current.account),
      storage: storage_summary }
  end

  # o que é NOSSO: quanto histórico já está guardado aqui, independente da Meta
  def storage_summary
    insights = Crm::AdInsight.where(account_id: Current.account.id)
    creatives = Crm::AdCreative.where(account_id: Current.account.id)
    { ads: creatives.count, gone_on_meta: creatives.where(effective_status: %w[DELETED ARCHIVED]).count,
      rows: insights.count, days: insights.distinct.count(:date), since: insights.minimum(:date), until: insights.maximum(:date),
      thumbnails: creatives.joins(:thumbnail_attachment).count, max_days: Crm::AdInsightsSyncService::MAX_DAYS }
  end

  def sync_state
    state = Crm::AdInsightsSyncService.state(Current.account)
    state.merge('running' => running?)
  end

  def running?
    started = Crm::AdInsightsSyncService.state(Current.account)['running_since']
    started.present? && Time.zone.parse(started) > RUNNING_STALE.ago
  rescue ArgumentError
    false
  end

  def too_soon?
    synced = Crm::AdInsightsSyncService.state(Current.account)['synced_at']
    synced.present? && Time.zone.parse(synced) > Crm::AdInsightsSyncService::MIN_MANUAL_GAP.ago && !params[:force]
  rescue ArgumentError
    false
  end

  def period_dates
    @period_dates ||= (standard_period_range || []).map(&:to_date)
  end

  def since_date
    @since_date ||= period_dates.first || (Date.current - 29)
  end

  def until_date
    @until_date ||= period_dates.last || Date.current
  end
end
