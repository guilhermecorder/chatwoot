class Api::V1::Accounts::Crm::DashboardsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  before_action -> { require_capability(:reports) }
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    pipeline = Current.account.crm_pipelines.includes(:stages).find(params[:pipeline_id])
    since, until_at = resolve_range

    # sem ORDER BY na base: as consultas agrupadas (group/count/sum) do
    # dashboard quebram no Postgres se herdarem a ordenação
    contacts = pipeline.crm_contacts
    # COORTE do período: cards cujo LEAD surgiu dentro do range escolhido
    # (data real do contato, não a do card). TODOS os blocos do dashboard
    # respondem ao seletor de período através dela — pedido do refino 28/07.
    cohort = contacts.joins(:contact).where(contacts: { created_at: since..until_at })

    render json: {
      pipeline_id:        pipeline.id,
      pipeline_name:      pipeline.name,
      period_days:        ((until_at - since) / 1.day).ceil,
      kpis:               build_kpis(pipeline, contacts, cohort, since, until_at),
      funnel:             build_funnel(pipeline, cohort),
      value_by_stage:     build_value_by_stage(pipeline, cohort),
      avg_time_by_stage:  build_avg_time_by_stage(pipeline, cohort),
      by_inbox:           build_by_inbox(since, until_at),
      created_over_time:  build_created_over_time(pipeline, contacts, since, until_at),
      responsiveness:     build_responsiveness(pipeline, cohort),
      agents:             build_agents(since, until_at),
      sheet_surgeries:    build_sheet_surgeries(since, until_at),
      by_label:           build_by_label(cohort),
      radar:              build_radar(since, until_at),
      nps:                build_nps(pipeline, cohort),
    }
  end

  private

  # período no fuso da clínica (São Paulo) — antes usava o fuso do servidor
  # (UTC): "hoje" começava às 21h da véspera e os números não batiam com o
  # Meu Painel/Agenda (que já eram SP). Presets hoje/ontem/semana ou N dias.
  def resolve_range
    now = TZ.now
    case params[:preset]
    when 'today'     then [now.beginning_of_day, now]
    when 'yesterday' then [now.yesterday.beginning_of_day, now.yesterday.end_of_day]
    when 'week'      then [now.beginning_of_week.beginning_of_day, now]
    else
      period = [[params[:period].to_i, 7].max, 1825].min
      [(now - period.days).beginning_of_day, now]
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

  def build_kpis(pipeline, contacts, cohort, since, until_at)
    total        = contacts.count
    cohort_total = cohort.count
    # mesma régua do Meu Painel (Crm::LeadsUniverse): contatos novos das
    # caixas de captação — os dois ambientes mostram o MESMO número
    new_in_period = Crm::LeadsUniverse.scope(Current.account, since, until_at).count

    # "fechou" = chegou à coluna de cirurgia (sem pós/indicação) ou além —
    # mesma régua do Meu Painel; antes era só a ÚLTIMA coluna (Pós Operatório)
    closing_ids   = closing_stage_ids(pipeline)
    closed_cohort = closing_ids.any? ? cohort.where(stage_id: closing_ids) : cohort.none
    closed_count  = closed_cohort.count
    close_rate    = cohort_total.positive? ? ((closed_count.to_f / cohort_total) * 100).round(1) : 0
    closed_value  = closed_cohort.sum('COALESCE(value, 0)').to_f.round(2)

    # Tempo médio de conversão dos leads do período que fecharam
    avg_conversion_minutes = if closed_count.positive?
      Crm::StageLog
        .where(crm_contact_id: closed_cohort.select(:id))
        .where.not(duration_minutes: nil)
        .group(:crm_contact_id)
        .sum(:duration_minutes)
        .values
        .then { |sums| sums.any? ? (sums.sum.to_f / sums.size).round(0) : nil }
    end

    {
      total_leads:             total,
      cohort_total:            cohort_total,
      new_in_period:           new_in_period,
      closed_value:            closed_value,
      close_rate:              close_rate,
      closed_count:            closed_count,
      avg_conversion_minutes:  avg_conversion_minutes,
    }
  end

  # colunas que valem como "fechou cirurgia": a coluna /cirurgia/ (sem pós e
  # sem indicação) e tudo que vem depois dela; sem coluna assim = última
  def closing_stage_ids(pipeline)
    ordered = pipeline.stages.sort_by(&:position)
    target = ordered.find { |s| closing_stage?(s) } || ordered.last
    return [] if target.nil?

    ordered.select { |s| s.position >= target.position }.map(&:id)
  end

  def closing_stage?(stage)
    stage.name.match?(/cirurgia/i) && !stage.name.match?(/pós|indica/i)
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
  # séries sobrepostas por COORTE: leads que chegaram naquele dia, e desses
  # quantos avançaram até Agendamento / Cirurgia. Tudo distribuído pela
  # data REAL do lead (contacts.created_at) — usar a data em que o card foi
  # movido criava picos artificiais nos dias de tratamento em massa.

  # granularidade inteligente: 1 dia = por HORA, até ~3 meses = por DIA,
  # acima disso = por SEMANA — o gráfico nunca vira 1 barra solitária nem
  # uma parede de 180 barras
  def build_created_over_time(pipeline, contacts, since, until_at)
    days = [((until_at.to_date - since.to_date).to_i + 1), 1].max
    granularity = :day
    granularity = :hour if days <= 1
    granularity = :week if days > 92

    series = timeline_series(pipeline, contacts, since, until_at, timeline_bucket_sql(granularity))

    timeline_keys(granularity, since, until_at).map do |key, label|
      {
        date: key,
        label: label,
        granularity: granularity,
        count: series[:novas][key] || 0,
        agendamentos: series[:agendamentos][key] || 0,
        cirurgias: series[:cirurgias][key] || 0,
      }
    end
  end

  def timeline_series(pipeline, contacts, since, until_at, bucket_sql)
    base = contacts.joins(:contact).where(contacts: { created_at: since..until_at })
    {
      novas: base.group(Arel.sql(bucket_sql)).count,
      agendamentos: reached_stage_scope(pipeline, contacts, since, until_at, /agendamento/i)
        .group(Arel.sql(bucket_sql)).count,
      cirurgias: reached_stage_scope(pipeline, contacts, since, until_at, /cirurgia/i, exclude: /pós|indica/i)
        .group(Arel.sql(bucket_sql)).count
    }
  end

  TIMELINE_TZ_SQL = "contacts.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo'".freeze

  def timeline_bucket_sql(granularity)
    case granularity
    when :hour then "to_char(#{TIMELINE_TZ_SQL}, 'HH24')"
    when :week then "to_char(date_trunc('week', #{TIMELINE_TZ_SQL}), 'YYYY-MM-DD')"
    else "to_char(#{TIMELINE_TZ_SQL}, 'YYYY-MM-DD')"
    end
  end

  # [chave do bucket, rótulo pronto pro gráfico]
  def timeline_keys(granularity, since, until_at)
    case granularity
    when :hour then (0..23).map { |h| [format('%02d', h), "#{format('%02d', h)}h"] }
    when :week then week_keys(since, until_at)
    else (since.to_date..until_at.to_date).map { |d| [d.iso8601, d.strftime('%d/%m')] }
    end
  end

  def week_keys(since, until_at)
    keys = []
    day = since.to_date.beginning_of_week
    while day <= until_at.to_date
      keys << [day.iso8601, "sem. #{day.strftime('%d/%m')}"]
      day += 7
    end
    keys
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

  # ── NPS do pós-operatório ──────────────────────────────────────────
  # % de satisfação a partir das etiquetas do agente de NPS
  # (nps-9-10 / nps-7-8 / nps-0-6), com recorte nos cards que chegaram
  # ao pós-operatório (se a coluna existir; senão, funil inteiro).
  def build_nps(pipeline, contacts)
    pos_stage = pipeline.stages.detect { |st| st.name.match?(/p[oó]s/i) }
    scope_ids = if pos_stage
                  ordered = pipeline.stages.sort_by(&:position)
                  ids = ordered.select { |st| st.position >= pos_stage.position }.map(&:id)
                  contacts.where(stage_id: ids).select(:contact_id)
                else
                  contacts.select(:contact_id)
                end

    counts = ActsAsTaggableOn::Tagging
             .joins(:tag)
             .where(taggable_type: 'Contact', context: 'labels')
             .where(taggable_id: scope_ids)
             .where(tags: { name: Crm::NpsService::NPS_LABELS })
             .group('tags.name')
             .count

    bands = [
      { key: 'nps-9-10', label: '😍 Notas 9 a 10 (promotores)' },
      { key: 'nps-7-8',  label: '🙂 Notas 7 a 8' },
      { key: 'nps-5-6',  label: '😐 Notas 5 a 6' },
      { key: 'nps-3-4',  label: '😕 Notas 3 a 4' },
      { key: 'nps-1-2',  label: '😞 Notas 1 a 2 (detratores)' }
    ].map { |b| b.merge(count: counts[b[:key]].to_i) }

    total = bands.sum { |b| b[:count] }
    promoters = bands.first[:count]
    detractors_low = counts['nps-5-6'].to_i + counts['nps-3-4'].to_i + counts['nps-1-2'].to_i
    {
      stage_name: pos_stage&.name,
      bands: bands,
      total: total,
      satisfaction: total.positive? ? (promoters.to_f / total * 100).round(1) : nil,
      nps_score: total.positive? ? (((promoters - detractors_low).to_f / total) * 100).round : nil
    }
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

  # leads que chegaram ATÉ a etapa alvo (ou além) no período — visão de
  # coorte pela data do LEAD, imune a movimentações em massa
  def reached_stage_scope(pipeline, contacts, since, until_at, pattern, exclude: /pós/i)
    ordered = pipeline.stages.order(:position).to_a
    target = ordered.find { |s| s.name.match?(pattern) && !s.name.match?(exclude) }
    return contacts.none unless target

    reached_ids = ordered.select { |s| s.position >= target.position }.map(&:id)

    contacts
      .joins(:contact)
      .where(stage_id: reached_ids)
      .where(contacts: { created_at: since..until_at })
  end
end
