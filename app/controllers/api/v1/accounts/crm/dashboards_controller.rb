class Api::V1::Accounts::Crm::DashboardsController < Api::V1::Accounts::BaseController
  def show
    pipeline = Current.account.crm_pipelines.includes(:stages).find(params[:pipeline_id])
    period   = [[params[:period].to_i, 7].max, 365].min  # entre 7 e 365 dias
    since    = period.days.ago.beginning_of_day

    # sem ORDER BY na base: as consultas agrupadas (group/count/sum) do
    # dashboard quebram no Postgres se herdarem a ordenação
    contacts = pipeline.crm_contacts

    render json: {
      pipeline_id:        pipeline.id,
      pipeline_name:      pipeline.name,
      period_days:        period,
      kpis:               build_kpis(pipeline, contacts, since),
      funnel:             build_funnel(pipeline, contacts),
      value_by_stage:     build_value_by_stage(pipeline, contacts),
      avg_time_by_stage:  build_avg_time_by_stage(pipeline, contacts),
      by_origin:          build_by_origin(contacts),
      created_over_time:  build_created_over_time(contacts, since, period),
    }
  end

  private

  # ── KPIs ─────────────────────────────────────────────────────────

  def build_kpis(pipeline, contacts, since)
    total         = contacts.count
    new_in_period = contacts.where('crm_contacts.created_at >= ?', since).count
    total_value   = contacts.sum('COALESCE(value, 0)').to_f.round(2)

    # Última etapa (maior position) = etapa de fechamento
    closing_stage = pipeline.stages.order(position: :desc).first
    closed_count  = closing_stage ? contacts.where(stage: closing_stage).count : 0
    close_rate    = total > 0 ? ((closed_count.to_f / total) * 100).round(1) : 0

    # Tempo médio de conversão: soma das durações dos logs de quem chegou na última etapa
    avg_conversion_minutes = if closing_stage
      closed_contacts = contacts.where(stage: closing_stage)
      if closed_contacts.any?
        Crm::StageLog
          .where(crm_contact_id: closed_contacts.select(:id))
          .where.not(duration_minutes: nil)
          .group(:crm_contact_id)
          .sum(:duration_minutes)
          .values
          .then { |sums| sums.any? ? (sums.sum.to_f / sums.size).round(0) : nil }
      end
    end

    {
      total_leads:             total,
      new_in_period:           new_in_period,
      total_value:             total_value,
      close_rate:              close_rate,
      closed_count:            closed_count,
      avg_conversion_minutes:  avg_conversion_minutes,
    }
  end

  # ── Funil ─────────────────────────────────────────────────────────

  def build_funnel(pipeline, contacts)
    counts_by_stage = contacts.group(:stage_id).count

    pipeline.stages.order(:position).map do |stage|
      {
        stage_id:    stage.id,
        stage_name:  stage.name,
        stage_color: stage.color,
        count:       counts_by_stage[stage.id] || 0,
      }
    end
  end

  # ── Valor por etapa ───────────────────────────────────────────────

  def build_value_by_stage(pipeline, contacts)
    values_by_stage = contacts
      .where.not(value: nil)
      .group(:stage_id)
      .sum('COALESCE(value, 0)')
      .transform_values { |v| v.to_f.round(2) }

    pipeline.stages.order(:position).map do |stage|
      {
        stage_id:    stage.id,
        stage_name:  stage.name,
        stage_color: stage.color,
        value:       values_by_stage[stage.id] || 0,
      }
    end
  end

  # ── Tempo médio por etapa ─────────────────────────────────────────

  def build_avg_time_by_stage(pipeline, contacts)
    # Busca os logs de estágio dos contacts deste pipeline
    contact_ids = contacts.select(:id)

    avg_by_stage = Crm::StageLog
      .where(crm_contact_id: contact_ids)
      .where.not(duration_minutes: nil)
      .group(:stage_id)
      .average(:duration_minutes)
      .transform_values { |v| v.to_f.round(0).to_i }

    pipeline.stages.order(:position).map do |stage|
      {
        stage_id:         stage.id,
        stage_name:       stage.name,
        stage_color:      stage.color,
        avg_minutes:      avg_by_stage[stage.id] || 0,
      }
    end
  end

  # ── Por origem ────────────────────────────────────────────────────

  def build_by_origin(contacts)
    contacts
      .where.not(origin: [nil, ''])
      .group(:origin)
      .count
      .sort_by { |_, v| -v }
      .first(8)  # máximo 8 origens no gráfico
      .map { |origin, count| { origin: origin, count: count } }
  end

  # ── Leads criados ao longo do tempo ──────────────────────────────

  def build_created_over_time(contacts, since, period)
    # Agrupa por dia
    by_day = contacts
      .where('crm_contacts.created_at >= ?', since)
      .group("DATE(crm_contacts.created_at AT TIME ZONE 'UTC')")
      .count

    # Preenche os dias sem dados com 0
    (0...period).map do |days_ago|
      date = (Date.today - (period - 1 - days_ago).days)
      { date: date.iso8601, count: by_day[date] || 0 }
    end
  end
end
