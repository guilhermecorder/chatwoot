# Números do Dashboard de Ligações (§5 do contrato): KPIs, por atendente,
# por dia, por hora (horário de São Paulo), por motivo de fim e as 30 mais
# recentes. Volume de uma clínica é pequeno — as contas rodam em Ruby.
class Crm::Calls::DashboardService
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  ANSWERED = %w[accepted completed].freeze

  def initialize(account:, since:, until_at:, period: 'month')
    @account = account
    @since = since
    @until_at = until_at
    @period = period
  end

  def call
    {
      period: @period,
      kpis: kpis,
      by_agent: by_agent,
      by_day: by_day,
      by_hour: by_hour,
      by_reason: by_reason,
      recent: scope.recent_first.with_attached_recording.includes(:contact, :user, :conversation).limit(30).map(&:to_payload)
    }
  end

  private

  def scope
    @scope ||= Crm::Call.where(account_id: @account.id).in_period(@since, @until_at)
  end

  def inbound
    @inbound ||= scope.inbound
  end

  def answered_calls
    @answered_calls ||= scope.answered.select(:id, :user_id, :direction, :duration, :started_at, :answered_at, :ended_at).to_a
  end

  def kpis
    received = inbound.count
    answered = inbound.answered.count
    talks = answered_calls.map(&:talk_seconds)
    {
      received: received, answered: answered, missed: inbound.missed.count, rejected: inbound.rejected.count,
      outbound: scope.outbound.count, answer_rate: pct(answered, received),
      avg_wait_seconds: avg(wait_list), avg_talk_seconds: avg(talks), total_talk_seconds: talks.sum
    }
  end

  # segundos de espera de cada recebida atendida
  def wait_list
    inbound.where.not(answered_at: nil).pluck(:started_at, :answered_at).map { |started, answered| (answered - started).to_i }
  end

  def by_agent
    users = @account.users.where(id: answered_calls.filter_map(&:user_id).uniq).index_by(&:id)
    rows = answered_calls.group_by(&:user_id).filter_map do |user_id, calls|
      agent_row(user_id, calls, users[user_id]) if user_id
    end
    rows.sort_by { |row| -row[:answered] }
  end

  def agent_row(user_id, calls, user)
    talks = calls.map(&:talk_seconds)
    { user_id: user_id, name: user&.available_name || 'Sem atendente', answered: calls.size,
      total_talk_seconds: talks.sum, avg_talk_seconds: avg(talks) }
  end

  def by_day
    rows = inbound.pluck(:started_at, :status).group_by { |started_at, _status| started_at.in_time_zone(TZ).to_date }
    day_range(rows.keys).map do |date|
      statuses = (rows[date] || []).map(&:last)
      { date: date.iso8601, received: statuses.size,
        answered: statuses.count { |s| ANSWERED.include?(s) }, missed: statuses.count('missed') }
    end
  end

  # dias contínuos quando o período é curto; senão só os dias com ligação
  def day_range(days_with_calls)
    from = @since.in_time_zone(TZ).to_date
    to = @until_at.in_time_zone(TZ).to_date
    return (from..to).to_a if (to - from).to_i <= 366

    days_with_calls.sort
  end

  def by_hour
    counts = Array.new(24, 0)
    inbound.pluck(:started_at).each { |at| counts[at.in_time_zone(TZ).hour] += 1 }
    counts
  end

  def by_reason
    scope.group(:end_reason).count
         .map { |reason, count| { reason: reason.presence || 'unknown', count: count } }
         .sort_by { |row| -row[:count] }
  end

  def pct(part, total)
    total.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end

  def avg(values)
    values.empty? ? 0 : (values.sum.to_f / values.size).round
  end
end
