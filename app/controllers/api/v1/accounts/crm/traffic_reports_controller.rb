class Api::V1::Accounts::Crm::TrafficReportsController < Api::V1::Accounts::BaseController
  def show
    period = [[params[:period].to_i, 7].max, 365].min
    since = period.days.ago.beginning_of_day

    render json: {
      period_days: period,
      ads: ads_metrics(since),
      conversations_started: conversations_started(since),
      funnel_stages: funnel_stages,
      labels: label_counts,
      agents: agent_metrics(since)
    }
  end

  private

  def ads_metrics(since)
    Crm::MetaInsightsService.new(
      account: Current.account,
      since_date: since.to_date
    ).call
  end

  def conversations_started(since)
    Current.account.conversations.where('created_at >= ?', since).count
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
  def agent_metrics(since)
    agents = Current.account.users.map { |u| [u.id, u.name] }.to_h

    avg_first_response = Current.account.reporting_events
                                .where(name: 'first_response')
                                .where('created_at >= ?', since)
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
