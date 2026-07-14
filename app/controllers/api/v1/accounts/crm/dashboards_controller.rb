class Api::V1::Accounts::Crm::DashboardsController < Api::V1::Accounts::BaseController
  def show
    pipeline = Current.account.crm_pipelines.includes(:stages).find(params[:pipeline_id])
    since, until_at = resolve_range

    # sem ORDER BY na base: as consultas agrupadas (group/count/sum) do
    # dashboard quebram no Postgres se herdarem a ordenação
    contacts = pipeline.crm_contacts

    render json: {
      pipeline_id:        pipeline.id,
      pipeline_name:      pipeline.name,
      period_days:        ((until_at - since) / 1.day).ceil,
      kpis:               build_kpis(pipeline, contacts, since, until_at),
      funnel:             build_funnel(pipeline, contacts),
      value_by_stage:     build_value_by_stage(pipeline, contacts),
      avg_time_by_stage:  build_avg_time_by_stage(pipeline, contacts),
      by_inbox:           build_by_inbox(since, until_at),
      created_over_time:  build_created_over_time(contacts, since, until_at),
      responsiveness:     build_responsiveness(pipeline, contacts),
      agents:             build_agents(since, until_at),
      sheet_surgeries:    build_sheet_surgeries(since, until_at),
      by_label:           build_by_label(contacts),
      radar:              build_radar(since, until_at),
    }
  end

  private

  # período: presets hoje/ontem/semana ou N dias (comportamento antigo)
  def resolve_range
    case params[:preset]
    when 'today'     then [Date.current.beginning_of_day, Time.current]
    when 'yesterday' then [1.day.ago.beginning_of_day, 1.day.ago.end_of_day]
    when 'week'      then [Date.current.beginning_of_week.beginning_of_day, Time.current]
    else
      period = [[params[:period].to_i, 7].max, 1825].min
      [period.days.ago.beginning_of_day, Time.current]
    end
  end

  # ── Indicadores por agente (atendimento) ──────────────────────────
  # abertas, sem resposta (última msg é do paciente) e tempo médio de
  # primeira resposta no período — dá para ver o time e cada atendente
  def build_agents(since, until_at)
    open_by_agent = Current.account.conversations.open.group(:assignee_id).count

    unanswered_by_agent = Current.account.conversations
                                 .open
                                 .where.not(waiting_since: nil)
                                 .group(:assignee_id)
                                 .count

    avg_first_response = Current.account.reporting_events
                                .where(name: 'first_response')
                                .where(created_at: since..until_at)
                                .group(:user_id)
                                .average(:value)

    rows = Current.account.users.map do |u|
      {
        id: u.id,
        name: u.available_name,
        open: open_by_agent[u.id] || 0,
        unanswered: unanswered_by_agent[u.id] || 0,
        avg_first_response_seconds: avg_first_response[u.id]&.to_f&.round(0),
      }
    end

    {
      rows: rows.sort_by { |r| -r[:open] },
      unassigned: {
        open: open_by_agent[nil] || 0,
        unanswered: unanswered_by_agent[nil] || 0,
      },
    }
  end

  # ── Responsividade ────────────────────────────────────────────────
  # Funil ACUMULADO: quantos leads "chegaram até cada etapa ou além".
  # É o que revela quem avançou vs. quem ficou parado no começo — base
  # para campanhas de reativação.
  def build_responsiveness(pipeline, contacts)
    total = contacts.count
    return { total: 0, stages: [], stuck: { count: 0, pct: 0.0 } } if total.zero?

    counts_by_stage = contacts.group(:stage_id).count
    ordered = pipeline.stages.order(:position).to_a

    # de trás pra frente: cards "nesta etapa ou além"
    cumulative = 0
    reached = {}
    ordered.reverse_each do |stage|
      cumulative += (counts_by_stage[stage.id] || 0)
      reached[stage.id] = cumulative
    end

    stages = ordered.each_with_index.map do |stage, idx|
      count_here = counts_by_stage[stage.id] || 0
      reached_here = reached[stage.id]
      {
        stage_id:    stage.id,
        stage_name:  stage.name,
        stage_color: stage.color,
        position:    idx,
        count_here:  count_here,                                       # exatamente nesta etapa
        reached:     reached_here,                                     # nesta ou além
        reached_pct: ((reached_here.to_f / total) * 100).round(1),     # % que chegou até aqui
      }
    end

    # "pouco responsivo" = parado na primeira etapa (não avançou de lugar)
    first = ordered.first
    stuck_count = first ? (counts_by_stage[first.id] || 0) : 0

    {
      total: total,
      stages: stages,
      stuck: {
        count: stuck_count,
        pct:   ((stuck_count.to_f / total) * 100).round(1),
        stage_name: first&.name,
      },
    }
  end

  # ── KPIs ─────────────────────────────────────────────────────────

  def build_kpis(pipeline, contacts, since, until_at)
    total         = contacts.count
    # data do lead = quando o contato surgiu (histórico real), não quando o
    # card foi criado no CRM (que pode ter sido hoje, na importação)
    new_in_period = contacts.joins(:contact).where(contacts: { created_at: since..until_at }).count
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

  # ── Origem = volume de conversas por caixa de entrada ─────────────

  def build_by_inbox(since, until_at)
    Current.account.conversations
           .where(created_at: since..until_at)
           .joins(:inbox)
           .group('inboxes.name')
           .count
           .sort_by { |_, v| -v }
           .first(8)
           .map { |name, count| { inbox: name, count: count } }
  end

  # ── Conversas ao longo do tempo + marcos da jornada ──────────────
  # séries sobrepostas: conversas novas, entradas em Agendamento e em
  # Cirurgia (via stage_logs — o momento em que o card ENTROU na etapa)

  def build_created_over_time(contacts, since, until_at)
    days = [((until_at.to_date - since.to_date).to_i + 1), 1].max

    # Usa a data de criação do CONTATO (histórico real), não a do card
    by_day = contacts
      .joins(:contact)
      .where(contacts: { created_at: since..until_at })
      .group("DATE(contacts.created_at AT TIME ZONE 'UTC')")
      .count

    schedule_by_day = stage_entries_by_day(contacts, since, until_at, '%agendamento%')
    surgery_by_day  = stage_entries_by_day(contacts, since, until_at, '%cirurgia%')

    (0...days).map do |i|
      date = since.to_date + i
      {
        date: date.iso8601,
        count: by_day[date] || 0,
        agendamentos: schedule_by_day[date] || 0,
        cirurgias: surgery_by_day[date] || 0,
      }
    end
  end

  # ── Etiquetas: volume e proporção entre os leads do funil ─────────

  def build_by_label(contacts)
    counts = ActsAsTaggableOn::Tagging
             .joins(:tag)
             .where(taggable_type: 'Contact', context: 'labels')
             .where(taggable_id: contacts.select(:contact_id))
             .group('tags.name')
             .count

    total = counts.values.sum
    items = counts.sort_by { |_, v| -v }.first(12).map do |name, count|
      {
        label: name,
        count: count,
        pct: total.positive? ? (count.to_f / total * 100).round(1) : 0.0,
      }
    end
    { total: total, items: items }
  end

  # ── Radar de Oportunidades × Consultas agendadas ──────────────────

  def build_radar(since, until_at)
    settings = CrmSetting.find_by(account: Current.account)
    history = Array(settings&.ai_config&.dig('opportunity_state', 'history'))
    detected = history.count do |h|
      t = begin
        Time.zone.parse(h['detected_at'].to_s)
      rescue StandardError
        nil
      end
      t.present? && t >= since && t <= until_at
    end

    appointments = Current.account.tasks
                          .where(task_type: 'consulta')
                          .where(created_at: since..until_at)
                          .count

    { opportunities: detected, appointments: appointments }
  end

  # ── Cirurgias da planilha (Google Sheets) ─────────────────────────
  # dados reais de fechamento que o Guilherme mantém na planilha —
  # filtrados pelo mesmo período do dashboard

  def build_sheet_surgeries(since, until_at)
    service = Crm::SheetsSurgeryService.new(account: Current.account)
    return { configured: false } unless service.configured?

    range = since.to_date..until_at.to_date
    rows = service.rows.select do |r|
      r['date'].present? && range.cover?(Date.parse(r['date']))
    rescue StandardError
      false
    end

    by_procedure = rows.group_by { |r| r['procedure'].presence || 'Não informado' }
                       .map { |name, list| { name: name, count: list.size, value: list.sum { |r| r['value_number'].to_f }.round(2) } }
                       .sort_by { |p| -p[:count] }
    by_unit = rows.group_by { |r| r['unit'].presence || 'Não informado' }
                  .map { |name, list| { name: name, count: list.size, value: list.sum { |r| r['value_number'].to_f }.round(2) } }
                  .sort_by { |u| -u[:count] }

    {
      configured: true,
      count: rows.size,
      revenue: rows.sum { |r| r['value_number'].to_f }.round(2),
      by_procedure: by_procedure.first(8),
      by_unit: by_unit,
    }
  rescue StandardError => e
    Rails.logger.error "[CrmDashboard] sheet_surgeries: #{e.message}"
    { configured: true, error: 'Não consegui ler a planilha agora.' }
  end

  def stage_entries_by_day(contacts, since, until_at, name_pattern)
    stage_ids = Crm::Stage.joins(:pipeline)
                          .where(crm_pipelines: { account_id: Current.account.id })
                          .where('crm_stages.name ILIKE ?', name_pattern)
                          .where.not('crm_stages.name ILIKE ?', '%pós%')
                          .pluck(:id)
    return {} if stage_ids.empty?

    Crm::StageLog
      .where(crm_contact_id: contacts.select(:id), stage_id: stage_ids)
      .where(entered_at: since..until_at)
      .group("DATE(entered_at AT TIME ZONE 'UTC')")
      .count
  end
end
