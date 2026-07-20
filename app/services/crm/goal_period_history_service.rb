# Matemática dos AMBIENTES DE META (item 58): dado um tipo de período
# (day/week/weekend/month/quarter/year), normaliza datas para o início do
# período e monta o histórico dos indicadores janela a janela — contagens
# agregadas no fuso de São Paulo e somadas em Ruby dentro de cada janela,
# então a MESMA conta serve para qualquer período. As metas de INDICADORES
# (%) saem sempre derivadas dos mesmos números, nunca digitadas à mão.
class Crm::GoalPeriodHistoryService
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  # quantos períodos entram no histórico de cada ambiente de meta
  PERIOD_COUNTS = { 'day' => 14, 'week' => 12, 'weekend' => 12, 'month' => 12, 'quarter' => 8, 'year' => 5 }.freeze

  def initialize(account, period)
    @account = account
    @period = period
  end

  # qualquer data dentro do período vira o INÍCIO dele (o que fica no banco)
  def normalize_start(date)
    case @period
    when 'day' then date
    when 'week' then date.beginning_of_week
    when 'weekend' then date.beginning_of_week + 5 # sábado da semana corrente
    when 'quarter' then date.beginning_of_quarter
    when 'year' then date.beginning_of_year
    else date.beginning_of_month
    end
  end

  def period_end(start)
    case @period
    when 'day' then start
    when 'week' then start + 6
    when 'weekend' then start + 1 # sábado + domingo
    when 'quarter' then start.end_of_quarter
    when 'year' then start.end_of_year
    else start.end_of_month
    end
  end

  def prev_start(start)
    case @period
    when 'day' then start - 1
    when 'week', 'weekend' then start - 7
    when 'quarter' then start << 3
    when 'year' then start << 12
    else start << 1
    end
  end

  # [{ month:, values: {contagens + %}, targets: }] — um por janela,
  # terminando na janela que contém HOJE
  def history(scoped_plans)
    starts = window_starts
    rows = indicator_rows(starts.first.in_time_zone(TZ), period_end(starts.last).in_time_zone(TZ).end_of_day)
    plans = scoped_plans.where(month: starts.first..).index_by { |p| p.month.iso8601 }

    starts.map do |p_start|
      values = values_between(rows, p_start, period_end(p_start))
      { month: p_start.iso8601, values: values.merge(rates_for(values)), targets: plans[p_start.iso8601]&.targets || {} }
    end
  end

  private

  def window_starts
    starts = [normalize_start(TZ.now.to_date)]
    (PERIOD_COUNTS[@period] - 1).times { starts.unshift(prev_start(starts.first)) }
    starts
  end

  # uma consulta agrupada por indicador; janelas curtas agregam por DIA
  # local, longas por MÊS local
  def indicator_rows(from, to) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    gran = %w[day week weekend].include?(@period) ? 'day' : 'month'
    trunc = ->(col) { Arel.sql("date_trunc('#{gran}', (#{col} AT TIME ZONE 'UTC') AT TIME ZONE 'America/Sao_Paulo')") }

    {
      'new_leads' => Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id })
                                 .where(crm_contacts: { created_at: from..to })
                                 .group(trunc.call('crm_contacts.created_at')).count,
      'appointments_booked' => @account.tasks.where(task_type: 'consulta', created_at: from..to)
                                       .group(trunc.call('tasks.created_at')).count,
      'consultations_attended' => @account.tasks.where(task_type: 'consulta', attendance: 'attended', due_at: from..to)
                                          .group(trunc.call('tasks.due_at')).count,
      'surgeries_booked' => @account.tasks.where(task_type: 'cirurgia', created_at: from..to)
                                    .group(trunc.call('tasks.created_at')).count,
      'surgeries_done' => @account.tasks.where(task_type: 'cirurgia', attendance: 'attended', due_at: from..to)
                                  .group(trunc.call('tasks.due_at')).count,
      'revenue_closed' => Crm::StageLog.joins(crm_contact: :pipeline)
                                       .where(crm_pipelines: { account_id: @account.id }, event_type: 'entered')
                                       .where('stage_name ILIKE ?', '%cirurgia realizada%')
                                       .where(entered_at: from..to)
                                       .group(trunc.call('crm_contact_stage_logs.entered_at'))
                                       .sum('crm_contacts.value')
    }
  end

  def values_between(rows, p_start, p_end)
    values = rows.transform_values { |counts| sum_in(counts, p_start, p_end) }
    values['revenue_closed'] = values['revenue_closed'].to_f.round
    values
  end

  def sum_in(counts, p_start, p_end)
    counts.sum { |at, v| at.to_date.between?(p_start, p_end) ? v : 0 }
  end

  # % oficiais: calculadas sempre dos mesmos números
  def rates_for(values)
    pct = lambda do |num, den|
      den.to_f.positive? ? ((num.to_f / den) * 100).round(1) : 0
    end
    {
      'rate_scheduling' => pct.call(values['appointments_booked'], values['new_leads']),
      'rate_attendance' => pct.call(values['consultations_attended'], values['appointments_booked']),
      'rate_surgery' => pct.call(values['surgeries_booked'], values['consultations_attended'])
    }
  end
end
