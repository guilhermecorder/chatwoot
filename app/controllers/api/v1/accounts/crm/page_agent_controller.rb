# 📄 AGENTE DE PÁGINAS (item 353): a tecnologia da Central de Criativos nas
# páginas — placar de cada página contra a média e o recorde da casa, pódio
# (título / corpo / convite), linha do tempo com as marcas do que mudou e a
# fila de recomendações (aprovar → fazer à mão → aprender). Nó
# marketing.resultados: ver = lê; editar = decide, marca feito, pede leitura.
class Api::V1::Accounts::Crm::PageAgentController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  before_action :set_action, only: [:decide, :manual]

  # GET /crm/page_agent?preset=month&page_ids[]=
  def show # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    since, until_at = standard_period_range || default_range
    report = Cevico::TrafficReport.new(account, since.to_date, until_at.to_date, page_ids: page_ids)
    records = Cevico::PageAgent::Records.new(account: account).call
    gsc = search_console_pages
    rows = report.rows.select { |r| r[:page_id] }
    pages = account.cevico_pages.where(id: rows.pluck(:page_id)).index_by(&:id)
    scorecards = rows.to_h do |row|
      rates = Cevico::PageAgent::Rates.for(row, gsc[row[:page_id]])
      card = Cevico::PageAgent::Scorecard.new(rates: rates, averages: records[:averages], records: records[:records], page_id: row[:page_id]).call
      [row[:page_id], card.merge(rates: rates, title: row[:title], emoji: row[:emoji], slug: row[:slug], views: row[:views], leads: row[:leads],
                                 booked: row[:booked], public_url: row[:public_url], builder_url: builder_url_for(pages[row[:page_id]]))]
    end
    render json: {
      period: { from: since.to_date.iso8601, to: until_at.to_date.iso8601 },
      averages: records[:averages], records: records[:records], records_window: { since: records[:since], until: records[:until] },
      scorecards: scorecards,
      podium: Cevico::PageAgent::Podium.new(rows: rows, gsc: gsc, pages: pages).call,
      actions: actions_json,
      scoreboard: Cevico::CampaignAgent::Learning.scoreboard(account, channels: [Cevico::PageAgent::Daily::CHANNEL]),
      state: Cevico::PageAgent::Daily.state(account),
      can_edit: cevico_can?('marketing.resultados', :edit)
    }
  end

  # GET /crm/page_agent/timeline?page_id=&days=90
  def timeline
    page = account.cevico_pages.find(params[:page_id])
    render json: Cevico::PageAgent::Timeline.new(account: account, page: page, days: params[:days].presence || 90).call
  end

  # POST /crm/page_agent/decide { id, decision: approve | dismiss | reopen }
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

  # POST /crm/page_agent/manual { id } — "fiz à mão" (começa o antes × depois); aprovada → aplicada
  def manual
    @action.update!(status: 'approved', decided_at: Time.current, decided_by_id: Current.user.id) if @action.status == 'suggested'
    result = Cevico::CampaignAgent::Executor.new(account: account, user: Current.user).mark_manual(@action)
    render json: result.merge(action: @action.reload.as_json, actions: actions_json), status: result[:ok] ? :ok : :unprocessable_entity
  end

  # GET /crm/page_agent/steps?id= — o passo a passo de uma recomendação
  def steps
    action = Crm::CampaignAction.find_by(account_id: account.id, id: params[:id])
    return render json: { error: 'Recomendação não encontrada.' }, status: :not_found if action.nil?

    render json: { steps: Cevico::PageAgent::Executor.steps_for(action) }
  end

  # POST /crm/page_agent/run — "Ler agora"
  def run
    Crm::PageAgentJob.perform_later(account.id, force: true)
    render json: { queued: true }
  end

  private

  def account
    Current.account
  end

  def page_ids
    ids = Array(params[:page_ids]).map(&:to_i).reject(&:zero?)
    ids.presence
  end

  def search_console_pages
    data = Cevico::SearchConsoleReport.new(account).call
    return {} unless data.is_a?(Hash) && data[:ready]

    Array(data[:pages]).select { |p| p[:page_id] }.index_by { |p| p[:page_id] }
  rescue StandardError
    {}
  end

  # o ambiente de montagem (mesma regra dos Resultados de tráfego: só quem edita páginas)
  def builder_url_for(page)
    return nil if page.nil? || !cevico_can?('marketing.paginas', :edit)

    "#{Cevico::PublicSite.base_url}/p/rascunho/#{page.preview_token}?edit=#{page.edit_token}"
  end

  def set_action
    @action = Crm::CampaignAction.find_by(account_id: account.id, id: params[:id], channel: Cevico::PageAgent::Daily::CHANNEL)
    render json: { error: 'Recomendação não encontrada.' }, status: :not_found if @action.nil?
  end

  def bad(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def default_range
    now = PERIOD_TZ.now
    [now.beginning_of_month, now.end_of_day]
  end

  def actions_json
    scope = Crm::CampaignAction.where(account_id: account.id, channel: Cevico::PageAgent::Daily::CHANNEL)
    { open: scope.open.recent.map(&:as_json),
      history: scope.where.not(status: Crm::CampaignAction::OPEN).order(updated_at: :desc).limit(60).map(&:as_json) }
  end
end
