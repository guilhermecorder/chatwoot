# Números do Dashboard de Ligações (§5 do contrato): KPIs, por atendente,
# por dia, por hora (horário de São Paulo), por motivo de fim e as 30 mais
# recentes. Volume de uma clínica é pequeno — as contas rodam em Ruby.
# Item 169: + KPIs da assistente virtual (ai_answered / ai_outbound),
# humanos × assistente (by_handler) e resultados das ligações da IA (by_outcome).
# Item 176 (ambiente Chamadas): `overview` = tudo isso + comparação com o
# período anterior (previous), o que está acontecendo AGORA (live), as
# perdidas de hoje que ninguém retornou (missed_pending) e por caixa (by_inbox).
class Crm::Calls::DashboardService
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  ANSWERED = %w[accepted completed].freeze
  LIST_INCLUDES = %i[contact user conversation inbox].freeze

  def initialize(account:, since:, until_at:, period: 'month')
    @account = account
    @since = since
    @until_at = until_at
    @period = period
  end

  def call
    {
      period: @period,
      since: @since.iso8601,
      until: @until_at.iso8601,
      kpis: kpis,
      by_agent: by_agent,
      by_day: by_day,
      by_hour: by_hour,
      by_reason: by_reason,
      by_handler: by_handler,
      by_outcome: by_outcome,
      recent: scope.recent_first.with_attached_recording.includes(*LIST_INCLUDES).limit(30).map(&:to_payload)
    }
  end

  # ambiente Chamadas (item 176)
  def overview
    call.merge(previous: previous_kpis, live: live_calls, missed_pending: missed_pending, by_inbox: by_inbox)
  end

  # só os KPIs (comparação com o período anterior)
  def kpis_only
    kpis
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
    talks = answered_calls.map(&:talk_seconds)
    { total: scope.count, avg_wait_seconds: avg(wait_list), avg_talk_seconds: avg(talks), total_talk_seconds: talks.sum }
      .merge(inbound_kpis, outbound_kpis, ai_kpis)
  end

  def inbound_kpis
    received = inbound.count
    answered = inbound.answered.count
    { received: received, answered: answered, missed: inbound.missed.count, rejected: inbound.rejected.count,
      answer_rate: pct(answered, received) }
  end

  # feitas pela clínica (humanos + assistente) e quantas o paciente atendeu
  def outbound_kpis
    made = scope.outbound.count
    answered = scope.outbound.answered.count
    { outbound: made, outbound_answered: answered, outbound_answer_rate: pct(answered, made) }
  end

  # assistente virtual: recebidas atendidas por ela e ligações que ela fez
  def ai_kpis
    { ai_answered: inbound.by_ai.answered.count, ai_outbound: scope.outbound.by_ai.count }
  end

  # mesmos KPIs no período imediatamente anterior, com a mesma duração
  def previous_kpis
    length = @until_at - @since
    self.class.new(account: @account, since: @since - length, until_at: @since - 1.second, period: @period).kpis_only
  end

  # tocando ou em atendimento agora — independe do período escolhido
  def live_calls
    Crm::Call.where(account_id: @account.id).live.includes(*LIST_INCLUDES).map(&:to_payload)
  end

  # perdidas de HOJE (fuso de São Paulo) que ninguém retornou: não têm o evento
  # "returned", nem uma ligação da clínica para o mesmo paciente depois dela,
  # nem uma nova recebida do mesmo paciente que foi atendida
  def missed_pending
    missed = today_scope.inbound.where(status: %i[missed rejected]).includes(*LIST_INCLUDES).recent_first.to_a
    return [] if missed.empty?

    later = later_contacts(missed.filter_map(&:contact_id).uniq)
    missed.reject { |call| call.returned? || contacted_after?(later, call) }.map(&:to_payload)
  end

  def today_scope
    now = TZ.now
    Crm::Call.where(account_id: @account.id).in_period(now.beginning_of_day, now.end_of_day)
  end

  # [contact_id, started_at] das ligações de hoje que "resolvem" uma perdida:
  # a clínica ligou para o paciente, ou ele ligou de novo e foi atendido
  def later_contacts(contact_ids)
    today_scope.where(contact_id: contact_ids)
               .where('(direction = :out) OR (direction = :in AND status IN (:answered))',
                      out: Crm::Call.directions[:outbound], in: Crm::Call.directions[:inbound],
                      answered: [Crm::Call.statuses[:accepted], Crm::Call.statuses[:completed]])
               .pluck(:contact_id, :started_at)
  end

  def contacted_after?(later, call)
    later.any? { |contact_id, started_at| contact_id == call.contact_id && started_at > call.started_at }
  end

  def by_inbox
    names = @account.inboxes.where(id: scope.distinct.pluck(:inbox_id)).pluck(:id, :name).to_h
    rows = scope.group(:inbox_id, :direction).count.each_with_object({}) do |((inbox_id, direction), count), acc|
      row = acc[inbox_id] ||= { inbox_id: inbox_id, name: names[inbox_id] || "Caixa #{inbox_id}", inbound: 0, outbound: 0 }
      row[direction.to_sym] += count
    end
    rows.values.sort_by { |row| -(row[:inbound] + row[:outbound]) }
  end

  # humanos × assistente virtual: ligações e tempo falado
  def by_handler
    %w[human ai].map do |handler|
      calls = scope.where(handled_by: handler)
      talks = calls.answered.select(:id, :duration, :answered_at, :ended_at).map(&:talk_seconds)
      { handled_by: handler, count: calls.count, answered: talks.size, total_talk_seconds: talks.sum }
    end
  end

  # resultados das ligações da assistente já encerradas (rótulos pt-BR; sem resultado = outro)
  def by_outcome
    counts = scope.by_ai.where(status: Crm::Call::FINAL_STATUSES).group(:outcome).count
    counts.each_with_object(Hash.new(0)) { |(outcome, count), acc| acc[Crm::Call::OUTCOME_LABELS.key?(outcome.to_s) ? outcome : 'outro'] += count }
          .map { |outcome, count| { outcome: outcome, label: Crm::Call::OUTCOME_LABELS[outcome], count: count } }
          .sort_by { |row| -row[:count] }
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
      outbound: calls.count(&:outbound?), total_talk_seconds: talks.sum, avg_talk_seconds: avg(talks) }
  end

  # por dia: recebidas/atendidas/perdidas (só recebidas) + feitas pela clínica
  def by_day
    rows = scope.pluck(:started_at, :status, :direction).group_by { |started_at, _s, _d| started_at.in_time_zone(TZ).to_date }
    day_range(rows.keys).map do |date|
      entries = rows[date] || []
      inbound_statuses = entries.select { |_at, _s, direction| direction == 'inbound' }.map { |_at, status, _d| status }
      { date: date.iso8601, received: inbound_statuses.size,
        answered: inbound_statuses.count { |s| ANSWERED.include?(s) }, missed: inbound_statuses.count('missed'),
        outbound: entries.size - inbound_statuses.size }
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
