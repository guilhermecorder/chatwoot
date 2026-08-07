class Api::V1::Accounts::Crm::TrafficReportsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  # traz investimento em anúncios (Meta) → área de relatórios (padrão: só admin)
  before_action -> { require_capability(:reports) }

  HISTORY_WEEKS = 12

  def show
    since, until_at, period = resolve_window

    render json: {
      period_days: period,
      ads: ads_metrics(since, until_at),
      conversations_started: conversations_started(since, until_at),
      funnel_stages: funnel_stages(since, until_at),
      funnel_weeks: funnel_weeks,
      labels: label_counts,
      agents: agent_metrics(since, until_at)
    }
  end

  private

  # janela do relatório: régua padrão (preset) OU legado (period em dias /
  # from-até soltos)
  def resolve_window
    if (range = standard_period_range)
      since, until_at = range
      return [since, until_at, ((until_at - since) / 1.day).ceil]
    end

    if params[:from].present?
      since = Date.parse(params[:from]).beginning_of_day
      until_at = params[:to].present? ? Date.parse(params[:to]).end_of_day : Time.current
      [since, until_at, ((until_at - since) / 1.day).ceil]
    else
      period = [[params[:period].to_i, 7].max, 365].min
      [period.days.ago.beginning_of_day, Time.current, period]
    end
  rescue Date::Error
    period = 30
    [period.days.ago.beginning_of_day, Time.current, period]
  end

  def ads_metrics(since, until_at)
    Crm::MetaInsightsService.new(
      account: Current.account,
      since_date: since.to_date,
      until_date: until_at.to_date
    ).call
  end

  def conversations_started(since, until_at)
    Current.account.conversations.where(created_at: since..until_at).count
  end

  def funnel_pipeline
    @funnel_pipeline ||= if params[:pipeline_id].present?
                           Current.account.crm_pipelines.find_by(id: params[:pipeline_id])
                         else
                           Current.account.crm_pipelines.order(:position).first
                         end
  end

  # Etapas do funil AGORA POR PERÍODO: quantos leads ENTRARAM em cada coluna
  # dentro da janela (histórico de movimentação), + o retrato atual da coluna.
  # Antes era só o retrato atual — o funil ignorava a régua de datas.
  def funnel_stages(since, until_at)
    pipeline = funnel_pipeline
    return [] if pipeline.blank?

    current = pipeline.crm_contacts.group(:stage_id).count
    entered = Crm::StageLog.where(stage_id: pipeline.stages.select(:id),
                                  event_type: 'entered',
                                  entered_at: since..until_at)
                           .group(:stage_id).distinct.count(:crm_contact_id)

    pipeline.stages.order(:position).map do |stage|
      {
        stage_id: stage.id,
        name: stage.name,
        color: stage.color,
        count: entered[stage.id] || 0,
        current: current[stage.id] || 0
      }
    end
  end

  # Série SEMANAL (últimas 12 semanas) de entradas por coluna + conversas —
  # alimenta a tendência, o mapa de calor e a linha de média dos dashboards.
  def funnel_weeks
    pipeline = funnel_pipeline
    return nil if pipeline.blank?

    tz = PERIOD_TZ
    start = tz.now.beginning_of_week - (HISTORY_WEEKS - 1).weeks
    week_expr = Arel.sql("date_trunc('week', (entered_at AT TIME ZONE 'UTC') AT TIME ZONE 'America/Sao_Paulo')")

    logs = Crm::StageLog.where(stage_id: pipeline.stages.select(:id), event_type: 'entered')
                        .where('entered_at >= ?', start)
                        .group(:stage_id, week_expr)
                        .distinct.count(:crm_contact_id)
    logs = logs.transform_keys { |stage_id, week| [stage_id, week.to_date] }

    conv_expr = Arel.sql("date_trunc('week', (conversations.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'America/Sao_Paulo')")
    conversations = Current.account.conversations.where('conversations.created_at >= ?', start)
                           .group(conv_expr).count
                           .transform_keys(&:to_date)

    weeks = (0...HISTORY_WEEKS).map { |i| (start + i.weeks).to_date }

    {
      weeks: weeks.map(&:iso8601),
      conversations: weeks.map { |w| conversations[w] || 0 },
      stages: pipeline.stages.order(:position).map do |stage|
        {
          stage_id: stage.id,
          name: stage.name,
          color: stage.color,
          counts: weeks.map { |w| logs[[stage.id, w]] || 0 }
        }
      end
    }
  end

  # Quantificação de contatos por etiqueta (top 20)
  def label_counts
    label_colors = Current.account.labels.pluck(:title, :color).to_h

    ActsAsTaggableOn::Tagging
      .where(taggable_type: 'Contact', context: 'labels',
             taggable_id: Current.account.contacts.select(:id))
      .joins(:tag)
      .group('tags.name')
      .count
      .sort_by { |_, count| -count }
      .first(20)
      .map { |name, count| { label: name, count: count, color: label_colors[name] } }
  end

  # Por agente: tempo médio de primeira resposta no período + conversas abertas
  def agent_metrics(since, until_at)
    agents = Current.account.users.map { |u| [u.id, u.name] }.to_h

    avg_first_response = Current.account.reporting_events
                                .where(name: 'first_response')
                                .where(created_at: since..until_at)
                                .group(:user_id)
                                .average(:value)

    open_by_agent = Current.account.conversations.open.group(:assignee_id).count

    rows = agents.map do |id, name|
      first_response = avg_first_response[id]
      open_count = open_by_agent[id] || 0
      next if first_response.nil? && open_count.zero?

      {
        id: id,
        name: name,
        avg_first_response_seconds: first_response&.to_f&.round(0),
        open_conversations: open_count
      }
    end.compact

    {
      rows: rows.sort_by { |r| -r[:open_conversations] },
      unassigned_open: open_by_agent[nil] || 0
    }
  end
end
