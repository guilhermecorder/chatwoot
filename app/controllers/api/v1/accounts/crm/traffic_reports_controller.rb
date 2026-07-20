class Api::V1::Accounts::Crm::TrafficReportsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  # traz investimento em anúncios (Meta) → área de relatórios (padrão: só admin)
  before_action -> { require_capability(:reports) }

  def show
    since, until_at, period = resolve_window

    render json: {
      period_days: period,
      ads: ads_metrics(since, until_at),
      conversations_started: conversations_started(since, until_at),
      funnel_stages: funnel_stages,
      labels: label_counts,
      agents: agent_metrics(since, until_at)
    }
  end

  private

  # janela do relatório: período em dias OU intervalo PERSONALIZADO (de/até)
  def resolve_window
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

  # Etapas do funil = colunas do pipeline do CRM com a contagem atual de cards
  def funnel_stages
    pipeline = if params[:pipeline_id].present?
                 Current.account.crm_pipelines.find_by(id: params[:pipeline_id])
               else
                 Current.account.crm_pipelines.order(:position).first
               end
    return [] if pipeline.blank?

    counts = pipeline.crm_contacts.group(:stage_id).count
    pipeline.stages.order(:position).map do |stage|
      {
        stage_id: stage.id,
        name: stage.name,
        color: stage.color,
        count: counts[stage.id] || 0
      }
    end
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
