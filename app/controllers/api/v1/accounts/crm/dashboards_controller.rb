class Api::V1::Accounts::Crm::DashboardsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  before_action -> { require_capability(:reports) }
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    pipeline = Current.account.crm_pipelines.includes(:stages).find(params[:pipeline_id])
    since, until_at = resolve_range

    # sem ORDER BY na base: as consultas agrupadas (group/count/sum) do
    # dashboard quebram no Postgres se herdarem a ordenação
    all_contacts = pipeline.crm_contacts
    # FILTRO POR CAIXA DE ENTRADA (missão 03/08): quando o admin escolhe uma
    # caixa, o dashboard inteiro passa a olhar só os leads que CHEGARAM por
    # ela (caixa da primeira conversa do contato — ninguém conta duas vezes)
    contacts = filter_by_entry_inbox(all_contacts)
    # COORTE do período: cards cujo LEAD surgiu dentro do range escolhido
    # (data real do contato, não a do card). TODOS os blocos do dashboard
    # respondem ao seletor de período através dela — pedido do refino 28/07.
    cohort = contacts.joins(:contact).where(contacts: { created_at: since..until_at })
    # coorte SEM filtro de caixa: base do comparativo entre caixas, que
    # existe justamente para ver todas lado a lado
    full_cohort = all_contacts.joins(:contact).where(contacts: { created_at: since..until_at })

    render json: {
      pipeline_id: pipeline.id,
      pipeline_name: pipeline.name,
      period_days: ((until_at - since) / 1.day).ceil,
      inbox_filter: selected_inbox_ids,
      kpis: build_kpis(pipeline, contacts, cohort, since, until_at),
      funnel: build_funnel(pipeline, cohort),
      value_by_stage: build_value_by_stage(pipeline, cohort),
      avg_time_by_stage: build_avg_time_by_stage(pipeline, cohort),
      by_inbox: build_by_inbox(since, until_at),
      created_over_time: build_created_over_time(pipeline, contacts, since, until_at),
      responsiveness: build_responsiveness(pipeline, cohort),
      agents: build_agents(since, until_at),
      sheet_surgeries: build_sheet_surgeries(since, until_at),
      by_label: build_by_label(cohort),
      losses: build_losses(contacts, cohort, since, until_at),
      radar: build_radar(since, until_at),
      nps: build_nps(pipeline, cohort),
      inbox_results: build_inbox_results(pipeline, full_cohort, since, until_at),
      revenue_over_time: build_revenue_over_time(pipeline, full_cohort, since, until_at)
    }
  end

  # ── 📈 PRO MAX (item 129): séries DIÁRIAS para o estúdio de análise ──
  # Devolve o dia a dia de cada variável no período; o navegador agrega em
  # semana/mês, monta candles e desenha as AÇÕES DA EMPRESA por cima.
  PRO_MAX_TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  PRO_MAX_MAX_DAYS = 366

  def pro_series
    pipeline = Current.account.crm_pipelines.includes(:stages).find(params[:pipeline_id])
    from, to = pro_range
    dates = (from..to).to_a
    range = PRO_MAX_TZ.parse(from.iso8601).beginning_of_day..PRO_MAX_TZ.parse(to.iso8601).end_of_day

    day = ->(col) { Arel.sql("to_char(#{col} AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD')") }
    fill = ->(counts) { dates.map { |d| (counts[d.iso8601] || 0).to_f.round(2) } }

    new_conversations = Current.account.conversations.where(created_at: range)
                               .group(day.call('conversations.created_at')).count
    new_leads = pipeline.crm_contacts.joins(:contact)
                        .where(contacts: { created_at: range })
                        .group(day.call('contacts.created_at')).count
    stage_logs = Crm::StageLog.joins(:crm_contact)
                              .where(crm_contacts: { pipeline_id: pipeline.id })
                              .where(entered_at: range)
    entered = stage_logs.group(:stage_id).group(day.call('crm_contact_stage_logs.entered_at'))
                        .distinct.count(:crm_contact_id)
    revenue = stage_logs.where("crm_contact_stage_logs.stage_name ILIKE '%cirurgia realizada%'")
                        .group(day.call('crm_contact_stage_logs.entered_at'))
                        .sum('COALESCE(crm_contacts.value, 0)')

    series = [
      { key: 'new_conversations', label: 'Novas conversas', color: '#0EA5E9', unit: 'n',
        values: fill.call(new_conversations), default_on: true },
      { key: 'new_leads', label: 'Leads novos (funil)', color: '#6366F1', unit: 'n',
        values: fill.call(new_leads), default_on: true }
    ]
    pipeline.stages.order(:position).each do |stage|
      by_day = entered.each_with_object({}) { |((sid, d), n), h| h[d] = n if sid == stage.id }
      series << { key: "stage_#{stage.id}", label: "Entrou em #{stage.name}", color: stage.color,
                  unit: 'n', values: fill.call(by_day), default_on: false }
    end
    series << { key: 'revenue', label: 'Faturamento fechado (R$)', color: '#059669', unit: 'brl',
                values: fill.call(revenue), default_on: false }

    # ── por CAIXA DE ENTRADA (item 129B) ──────────────────────────────
    # conversas novas por caixa (dia a dia) + faturamento pela caixa de
    # ENTRADA do paciente (mesma régua de atribuição do dashboard:
    # primeira conversa numa porta de captação)
    inbox_palette = %w[#1D4ED8 #DB2777 #B8860B #059669 #7C3AED #0D9488 #EA580C #DC2626]
    inboxes = Current.account.inboxes.order(:id).to_a
    conv_by_inbox = Current.account.conversations.where(created_at: range)
                           .group(:inbox_id).group(day.call('conversations.created_at')).count
    rev_by_contact_day = stage_logs.where("crm_contact_stage_logs.stage_name ILIKE '%cirurgia realizada%'")
                                   .group('crm_contacts.contact_id')
                                   .group(day.call('crm_contact_stage_logs.entered_at'))
                                   .sum('COALESCE(crm_contacts.value, 0)')
    rev_by_inbox = Hash.new { |h, k| h[k] = {} }
    rev_by_contact_day.each do |(contact_id, d), value|
      inbox_id = entry_inbox_map[contact_id]
      next unless inbox_id

      rev_by_inbox[inbox_id][d] = (rev_by_inbox[inbox_id][d] || 0) + value.to_f
    end

    inboxes.each_with_index do |inbox, i|
      color = inbox_palette[i % inbox_palette.size]
      conv_days = conv_by_inbox.each_with_object({}) { |((iid, d), n), h| h[d] = n if iid == inbox.id }
      series << { key: "inbox_conv_#{inbox.id}", label: "Conversas · #{inbox.name}", color: color,
                  unit: 'n', values: fill.call(conv_days), default_on: false, group: 'inbox_conv' } if conv_days.any?
      rev_days = rev_by_inbox[inbox.id]
      series << { key: "inbox_rev_#{inbox.id}", label: "Faturamento · #{inbox.name}", color: color,
                  unit: 'brl', values: fill.call(rev_days), default_on: false, group: 'inbox_rev' } if rev_days.any?
    end

    actions = Array((crm_settings&.agenda_config || {})['company_actions'])
              .select { |a| a['date'].to_s.between?(from.iso8601, to.iso8601) }

    render json: {
      from: from.iso8601, to: to.iso8601,
      dates: dates.map(&:iso8601),
      labels: dates.map { |d| d.strftime('%d/%m') },
      series: series,
      actions: actions
    }
  end

  # ── 🟥 Lista de resgate (item 145): os pacientes de UM motivo de perda ──
  # A tela de perdas clica no motivo e recebe quem está lá — nome, telefone,
  # coluna, valor e há quantos dias parou. Matéria-prima da campanha de
  # resgate (Colheitadeira / Tratamento de dados).
  def loss_contacts # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    pipeline = Current.account.crm_pipelines.includes(:stages).find(params[:pipeline_id])
    since, until_at = resolve_range
    tag = params[:label].to_s
    return render json: { items: [] } unless tag.start_with?('perda_')

    contacts = filter_by_entry_inbox(pipeline.crm_contacts)
    cohort = contacts.joins(:contact).where(contacts: { created_at: since..until_at })
    rows = cohort
           .joins("INNER JOIN taggings tg ON tg.taggable_type = 'Contact' AND tg.context = 'labels' " \
                  'AND tg.taggable_id = crm_contacts.contact_id')
           .joins('INNER JOIN tags ON tags.id = tg.tag_id')
           .where(tags: { name: tag })
           .select('crm_contacts.*, contacts.name AS contact_name, contacts.phone_number AS contact_phone')
           .order(Arel.sql('COALESCE(crm_contacts.value, 0) DESC, crm_contacts.id DESC'))
           .limit(100)
    stage_names = pipeline.stages.index_by(&:id)
    render json: {
      label: tag,
      items: rows.map do |c|
        moved = c.stage_moved_at || c.created_at
        {
          contact_id: c.contact_id,
          name: c.contact_name.presence || 'Sem nome',
          phone: c.contact_phone,
          value: c.value.to_f.round(2),
          stage_name: stage_names[c.stage_id]&.name,
          days_still: moved ? ((Time.current - moved) / 1.day).floor : nil
        }
      end
    }
  end

  private

  def pro_range
    to = begin
      Date.iso8601(params[:to].to_s)
    rescue StandardError
      PRO_MAX_TZ.today
    end
    from = begin
      Date.iso8601(params[:from].to_s)
    rescue StandardError
      to - 89
    end
    from = to - (PRO_MAX_MAX_DAYS - 1) if (to - from).to_i >= PRO_MAX_MAX_DAYS
    [from, [to, from].max]
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: Current.account)
  end

  # ── Filtro por caixa de entrada ───────────────────────────────────
  # Regra de atribuição: a caixa "dona" do lead é a da primeira conversa
  # dele NUMA PORTA DE ENTRADA (caixa de captação). Caixas operacionais
  # (Confirmação de Consulta, NPS...) recebem pacientes que já chegaram
  # pelas portas — só ficam com quem NUNCA passou por porta nenhuma
  # (importados/walk-ins). Ajuste de precisão pedido 03/08.

  def selected_inbox_ids
    @selected_inbox_ids ||= begin
      wanted = Array(params[:inbox_ids]).map(&:to_i).reject(&:zero?)
      wanted.any? ? (wanted & Current.account.inboxes.pluck(:id)) : []
    end
  end

  def inbox_filter_active?
    selected_inbox_ids.any?
  end

  def capture_inbox_ids
    @capture_inbox_ids ||= Crm::LeadsUniverse.capture_inbox_ids(Current.account)
  end

  # SQL da caixa de chegada por contato (ids já validados contra a conta):
  # a primeira conversa numa PORTA DE ENTRADA vence; sem nenhuma, vale a
  # primeira conversa de qualquer caixa
  def entry_inbox_sql
    priority = capture_inbox_ids.any? ? "(CASE WHEN inbox_id IN (#{capture_inbox_ids.join(',')}) THEN 0 ELSE 1 END)," : ''
    <<~SQL.squish
      SELECT DISTINCT ON (contact_id) contact_id, inbox_id
      FROM conversations
      WHERE account_id = #{Current.account.id}
      ORDER BY contact_id, #{priority} created_at ASC, id ASC
    SQL
  end

  def entry_contact_ids_sql
    "SELECT fc.contact_id FROM (#{entry_inbox_sql}) fc WHERE fc.inbox_id IN (#{selected_inbox_ids.join(',')})"
  end

  def filter_by_entry_inbox(contacts_scope)
    return contacts_scope unless inbox_filter_active?

    contacts_scope.where("crm_contacts.contact_id IN (#{entry_contact_ids_sql})")
  end

  # contact_id → inbox_id da primeira conversa (conta inteira, 1 query)
  def entry_inbox_map
    @entry_inbox_map ||= ActiveRecord::Base.connection
                                           .select_rows(entry_inbox_sql)
                                           .to_h
  end

  # período no fuso da clínica (São Paulo) — antes usava o fuso do servidor
  # (UTC): "hoje" começava às 21h da véspera e os números não batiam com o
  # Meu Painel/Agenda (que já eram SP).
  # Régua padrão CEVICO (06/08) via concern; presets antigos (week / N dias)
  # continuam valendo por compatibilidade.
  def resolve_range
    standard_period_range || legacy_range
  end

  def legacy_range
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
    conv_scope = Current.account.conversations
    conv_scope = conv_scope.where(inbox_id: selected_inbox_ids) if inbox_filter_active?
    open_by_agent = conv_scope.open.group(:assignee_id).count

    unanswered_by_agent = conv_scope
                          .open
                          .where.not(waiting_since: nil)
                          .group(:assignee_id)
                          .count

    events_scope = Current.account.reporting_events
    events_scope = events_scope.where(inbox_id: selected_inbox_ids) if inbox_filter_active?
    avg_first_response = events_scope
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
    universe = Crm::LeadsUniverse.scope(Current.account, since, until_at)
    universe = universe.where("contacts.id IN (#{entry_contact_ids_sql})") if inbox_filter_active?
    new_in_period = universe.count

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

  # item 145: além do valor total, quanto está PARADO na etapa (cards que
  # não se mexem há 15+ dias) — vira o aviso "R$ X parados em <coluna>"
  STALLED_AFTER_DAYS = 15

  def build_value_by_stage(pipeline, contacts) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    values_by_stage = contacts
      .where.not(value: nil)
      .group(:stage_id)
      .sum('COALESCE(value, 0)')
      .transform_values { |v| v.to_f.round(2) }
    counts_by_stage = contacts.group(:stage_id).count
    stalled = contacts.where('COALESCE(crm_contacts.stage_moved_at, crm_contacts.created_at) < ?',
                             STALLED_AFTER_DAYS.days.ago)
    stalled_counts = stalled.group(:stage_id).count
    stalled_values = stalled.group(:stage_id).sum('COALESCE(value, 0)').transform_values { |v| v.to_f.round(2) }

    pipeline.stages.order(:position).map do |stage|
      {
        stage_id:      stage.id,
        stage_name:    stage.name,
        stage_color:   stage.color,
        value:         values_by_stage[stage.id] || 0,
        count:         counts_by_stage[stage.id] || 0,
        stalled_count: stalled_counts[stage.id] || 0,
        stalled_value: stalled_values[stage.id] || 0,
        stalled_days:  STALLED_AFTER_DAYS,
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
    granularity = timeline_granularity(since, until_at)
    series = timeline_series(pipeline, contacts, since, until_at, timeline_bucket_sql(granularity))

    rows = timeline_keys(granularity, since, until_at).map do |key, label|
      {
        date: key,
        label: label,
        granularity: granularity,
        count: series[:novas][key] || 0,
        agendamentos: series[:agendamentos][key] || 0,
        cirurgias: series[:cirurgias][key] || 0,
      }
    end
    # apara o VAZIO da esquerda (era pré-sistema): o gráfico começa no
    # primeiro balde com movimento — pedido 11/08
    first = rows.index { |r| r[:count].positive? || r[:agendamentos].positive? || r[:cirurgias].positive? }
    first ? rows.drop(first) : rows
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

  # 1 dia = por hora; até 1 mês = por dia; acima = por SEMANA. Gráficos de
  # área com balde diário viram agulhas (refino 03/08) — semana dá as
  # colinas fluidas do modelo e alinha Conversas × Faturamento no mesmo eixo
  def timeline_granularity(since, until_at)
    days = [((until_at.to_date - since.to_date).to_i + 1), 1].max
    return :hour if days <= 1
    # período longo (1 ano+) em semanas virava parede de agulhas ilegível
    # (pedido 11/08) — acima de ~13 meses o balde vira MÊS
    return :month if days > 400
    return :week if days > 31

    :day
  end

  TIMELINE_TZ_SQL = "contacts.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo'".freeze

  def timeline_bucket_sql(granularity)
    case granularity
    when :hour then "to_char(#{TIMELINE_TZ_SQL}, 'HH24')"
    when :week then "to_char(date_trunc('week', #{TIMELINE_TZ_SQL}), 'YYYY-MM-DD')"
    when :month then "to_char(date_trunc('month', #{TIMELINE_TZ_SQL}), 'YYYY-MM-DD')"
    else "to_char(#{TIMELINE_TZ_SQL}, 'YYYY-MM-DD')"
    end
  end

  # [chave do bucket, rótulo pronto pro gráfico]
  def timeline_keys(granularity, since, until_at)
    case granularity
    when :hour then (0..23).map { |h| [format('%02d', h), "#{format('%02d', h)}h"] }
    when :week then week_keys(since, until_at)
    when :month then month_keys(since, until_at)
    else (since.to_date..until_at.to_date).map { |d| [d.iso8601, d.strftime('%d/%m')] }
    end
  end

  MESES_PT = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze

  def month_keys(since, until_at)
    keys = []
    d = since.to_date.beginning_of_month
    while d <= until_at.to_date
      keys << [d.iso8601, "#{MESES_PT[d.month - 1]}/#{d.strftime('%y')}"]
      d = d.next_month
    end
    keys
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

  # ── 🟥 Perdas por motivo v2 (item 145) ────────────────────────────
  # Por etiqueta perda_*: quantidade no período, tendência vs o período
  # anterior e o VALOR dos cards perdidos (só dos que têm valor preenchido —
  # sem estimativa inventada). Bloco próprio: não disputa espaço com o
  # top-12 do by_label.
  def build_losses(contacts, cohort, since, until_at) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    prev_until = since - 1.second
    prev_since = prev_until - (until_at - since)
    prev_cohort = contacts.joins(:contact).where(contacts: { created_at: prev_since..prev_until })

    tag_scope = ActsAsTaggableOn::Tagging
                .joins(:tag)
                .where(taggable_type: 'Contact', context: 'labels')
                .where("tags.name LIKE 'perda\\_%'")
    counts = tag_scope.where(taggable_id: cohort.select(:contact_id)).group('tags.name').count
    prev_counts = tag_scope.where(taggable_id: prev_cohort.select(:contact_id)).group('tags.name').count

    value_rows = cohort
                 .joins("INNER JOIN taggings tg ON tg.taggable_type = 'Contact' AND tg.context = 'labels' " \
                        'AND tg.taggable_id = crm_contacts.contact_id')
                 .joins('INNER JOIN tags ON tags.id = tg.tag_id')
                 .where("tags.name LIKE 'perda\\_%'")
                 .where('COALESCE(crm_contacts.value, 0) > 0')
                 .group('tags.name')
    values = value_rows.sum('crm_contacts.value')
    value_counts = value_rows.count

    {
      previous_label: "#{prev_since.strftime('%d/%m')}–#{prev_until.strftime('%d/%m')}",
      items: (counts.keys + prev_counts.keys).uniq.map do |name|
        {
          label: name,
          count: counts[name] || 0,
          prev: prev_counts[name] || 0,
          value: (values[name] || 0).to_f.round(2),
          value_count: value_counts[name] || 0
        }
      end
    }
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

    appointments_scope = Current.account.tasks
                                .where(task_type: 'consulta')
                                .where(created_at: since..until_at)
    # consultas seguem o filtro pela caixa de chegada do paciente da tarefa
    appointments_scope = appointments_scope.where("tasks.contact_id IN (#{entry_contact_ids_sql})") if inbox_filter_active?

    { opportunities: detected, appointments: appointments_scope.count }
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

  # ── Resultados por caixa de entrada (missão 03/08) ────────────────
  # Comparativo lado a lado: cada caixa com os leads do período que
  # CHEGARAM por ela, quantos avançaram até Agendamento, quantos fecharam
  # cirurgia e a receita. Com o investimento mensal informado (só admin),
  # calcula CPL, CAC, ROAS e ROI da caixa.

  def build_inbox_results(pipeline, full_cohort, since, until_at)
    stats = inbox_funnel_stats(pipeline, full_cohort)
    admin = Current.account_user&.administrator?
    investments = inbox_investments_config
    period_days = (until_at - since) / 1.day
    inbox_names = Current.account.inboxes.pluck(:id, :name).to_h

    result_rows = stats.map do |inbox_id, stat|
      row = inbox_result_row(inbox_id, stat, inbox_names)
      row.merge!(inbox_financials(inbox_id, stat, investments, period_days, since..until_at)) if admin
      row
    end

    {
      admin: admin,
      capture_inbox_ids: capture_inbox_ids,
      # portas de entrada primeiro, depois as operacionais, cada grupo por volume
      rows: result_rows.sort_by { |r| [r[:is_capture] ? 0 : 1, r[:inbox_id].nil? ? 1 : 0, -r[:leads]] }.first(8)
    }
  end

  # uma passada só pelos cards da coorte: leads/agendou/compareceu/fechou/
  # receita por caixa de chegada
  def inbox_funnel_stats(pipeline, full_cohort)
    sets = funnel_stage_sets(pipeline)
    stats = Hash.new { |h, k| h[k] = { leads: 0, scheduled: 0, attended: 0, closed: 0, revenue: 0.0 } }
    full_cohort.pluck(:contact_id, :stage_id, Arel.sql('COALESCE(crm_contacts.value, 0)')).each do |contact_id, stage_id, value|
      bump_inbox_stat(stats[entry_inbox_map[contact_id]], stage_id, value, sets)
    end
    stats
  end

  def funnel_stage_sets(pipeline)
    {
      sched: reached_ids_for(pipeline, /agendamento/i).to_set,
      attended: reached_ids_for(pipeline, /consulta realizada/i).to_set,
      closed: closing_stage_ids(pipeline).to_set
    }
  end

  def bump_inbox_stat(stat, stage_id, value, sets)
    stat[:leads] += 1
    stat[:scheduled] += 1 if sets[:sched].include?(stage_id)
    stat[:attended] += 1 if sets[:attended].include?(stage_id)
    return unless sets[:closed].include?(stage_id)

    stat[:closed] += 1
    stat[:revenue] += value.to_f
  end

  def inbox_result_row(inbox_id, stat, inbox_names)
    {
      inbox_id: inbox_id,
      name: inbox_id ? (inbox_names[inbox_id] || 'Caixa removida') : 'Sem conversa vinculada',
      is_capture: inbox_id.present? && capture_inbox_ids.include?(inbox_id),
      leads: stat[:leads],
      scheduled: stat[:scheduled],
      scheduling_rate: pct(stat[:scheduled], stat[:leads]),
      attended: stat[:attended],
      # % de comparecimento sobre quem AGENDOU — a régua que interessa
      attendance_rate: pct(stat[:attended], stat[:scheduled]),
      closed: stat[:closed],
      close_rate: pct(stat[:closed], stat[:leads]),
      revenue: stat[:revenue].round(2)
    }
  end

  def pct(part, total)
    total.positive? ? ((part.to_f / total) * 100).round(1) : 0.0
  end

  # Investimento da caixa no período — dois modos ("as coisas conversam",
  # pedido 03/08): manual = R$/mês informado, proporcional aos dias
  # (30,44 = mês médio); meta_auto = gasto REAL do período puxado da conta
  # de anúncios do Meta (mesma integração do Funil de Tráfego, cache 10min).
  # Google automático aguarda o developer token do Google Ads (pendente).
  def inbox_financials(inbox_id, stat, investments, period_days, range)
    cfg = investments[inbox_id.to_s]
    mode = cfg&.dig('mode')
    return empty_financials.merge(investment_mode: mode) if cfg.nil?

    case mode
    when 'meta_auto' then meta_auto_financials(stat, range)
    when 'google_auto' then google_auto_financials(stat, range)
    else
      monthly = cfg['monthly'].to_f
      return empty_financials.merge(investment_mode: 'manual') unless monthly.positive?

      build_financials(stat, (monthly * period_days / 30.44).round(2),
                       monthly: monthly.round(2), mode: 'manual')
    end
  end

  def meta_auto_financials(stat, range)
    meta = meta_spend_for(range.first, range.last)
    spend = meta[:spend].to_f
    unless spend.positive?
      reason = meta[:error].presence || (meta[:configured] ? 'sem gasto no período' : 'Meta Ads não configurado em Integrações')
      return empty_financials.merge(investment_mode: 'meta_auto', investment_note: reason)
    end

    build_financials(stat, spend.round(2), monthly: nil, mode: 'meta_auto')
  end

  # gasto do Google lido pela API de dados do GA4 (conta de serviço) —
  # não precisa do developer token do Google Ads
  def google_auto_financials(stat, range)
    data = google_cost_for(range.first, range.last)
    cost = data[:cost].to_f
    unless cost.positive?
      reason = data[:error].presence ||
               (data[:configured] ? 'sem gasto no período' : 'configure a conta de serviço em Integrações → Google Ads')
      return empty_financials.merge(investment_mode: 'google_auto', investment_note: reason)
    end

    build_financials(stat, cost, monthly: nil, mode: 'google_auto')
  end

  def google_cost_for(since, until_at)
    @google_cost_for ||= Rails.cache.fetch(
      ['cevico_google_cost', Current.account.id, since.to_date.iso8601, until_at.to_date.iso8601],
      expires_in: 10.minutes
    ) do
      Crm::GoogleAdCostService.new(account: Current.account, since_date: since.to_date, until_date: until_at.to_date).call
    end
  end

  def build_financials(stat, invest, monthly:, mode:)
    revenue = stat[:revenue]
    {
      investment_mode: mode,
      investment_monthly: monthly,
      investment_period: invest,
      cpl: cost_per(invest, stat[:leads]),
      cost_per_schedule: cost_per(invest, stat[:scheduled]),
      cost_per_attendance: cost_per(invest, stat[:attended]),
      cac: cost_per(invest, stat[:closed]),
      roas: (revenue / invest).round(2),
      roi_pct: (((revenue - invest) / invest) * 100).round(1)
    }
  end

  def cost_per(invest, count)
    count.to_i.positive? ? (invest / count).round(2) : nil
  end

  def empty_financials
    { investment_mode: nil, investment_monthly: nil, investment_period: nil, investment_note: nil,
      cpl: nil, cost_per_schedule: nil, cost_per_attendance: nil, cac: nil, roas: nil, roi_pct: nil }
  end

  # gasto real da conta de anúncios do Meta no período (cache curto: o
  # dashboard recarrega a cada clique de período/caixa)
  def meta_spend_for(since, until_at)
    @meta_spend_for ||= Rails.cache.fetch(
      ['cevico_meta_spend', Current.account.id, since.to_date.iso8601, until_at.to_date.iso8601],
      expires_in: 10.minutes
    ) do
      Crm::MetaInsightsService.new(account: Current.account, since_date: since.to_date, until_date: until_at.to_date).call
    end
  end

  # config por caixa no formato novo {mode, monthly}; número puro = legado manual
  def inbox_investments_config
    raw = CrmSetting.find_by(account: Current.account)&.agenda_config&.dig('inbox_investments') || {}
    raw.transform_values do |v|
      v.is_a?(Hash) ? v : { 'mode' => 'manual', 'monthly' => v.to_f }
    end
  end

  # etapas "nesta ou além" a partir da primeira que casa com o padrão
  def reached_ids_for(pipeline, pattern, exclude: /pós/i)
    ordered = pipeline.stages.sort_by(&:position)
    target = ordered.find { |s| s.name.match?(pattern) && !s.name.match?(exclude) }
    return [] unless target

    ordered.select { |s| s.position >= target.position }.map(&:id)
  end

  # ── Faturamento ao longo do tempo, por caixa de entrada ───────────
  # receita dos leads que FECHARAM, distribuída pela data de chegada do
  # lead (mesma régua de coorte do resto do dashboard) e separada pela
  # caixa de chegada — alimenta o gráfico de áreas em camadas.

  def build_revenue_over_time(pipeline, full_cohort, since, until_at)
    closed_ids = closing_stage_ids(pipeline)
    return { points: [], series: [] } if closed_ids.empty?

    granularity = timeline_granularity(since, until_at)
    keys = timeline_keys(granularity, since, until_at)
    by_inbox, totals = revenue_buckets(full_cohort, closed_ids, granularity)

    series = revenue_series(by_inbox, totals, keys)
    # mesmo corte do gráfico de conversas: sem meses vazios na esquerda
    first = keys.each_index.find { |i| series.any? { |s| s[:values][i].to_f.positive? } }
    if first&.positive?
      keys = keys.drop(first)
      series = series.map { |s| s.merge(values: s[:values].drop(first)) }
    end

    {
      granularity: granularity,
      points: keys.map { |k, label| { date: k, label: label } },
      series: series
    }
  end

  def revenue_buckets(full_cohort, closed_ids, granularity)
    by_inbox = Hash.new { |h, k| h[k] = Hash.new(0.0) }
    totals = Hash.new(0.0)
    full_cohort.where(stage_id: closed_ids)
               .pluck(:contact_id, Arel.sql('COALESCE(crm_contacts.value, 0)'), Arel.sql('contacts.created_at'))
               .each do |contact_id, value, created_at|
      inbox_id = entry_inbox_map[contact_id]
      by_inbox[inbox_id][revenue_bucket_key(created_at, granularity)] += value.to_f
      totals[inbox_id] += value.to_f
    end
    [by_inbox, totals]
  end

  # top 5 caixas por receita + "Outras caixas" agrupadas
  def revenue_series(by_inbox, totals, keys)
    inbox_names = Current.account.inboxes.pluck(:id, :name).to_h
    top = totals.sort_by { |_, v| -v }.first(5).map(&:first)

    series = top.map do |inbox_id|
      {
        inbox_id: inbox_id,
        name: inbox_id ? (inbox_names[inbox_id] || 'Caixa removida') : 'Sem conversa vinculada',
        values: keys.map { |k, _| by_inbox[inbox_id][k].round(2) }
      }
    end

    series + other_revenue_series(by_inbox, totals.keys - top, keys)
  end

  def other_revenue_series(by_inbox, other_ids, keys)
    return [] if other_ids.empty?

    [{
      inbox_id: 'outras',
      name: 'Outras caixas',
      values: keys.map { |k, _| other_ids.sum { |id| by_inbox[id][k] }.round(2) }
    }]
  end

  def revenue_bucket_key(time, granularity)
    t = time.in_time_zone(TZ)
    case granularity
    when :hour then format('%02d', t.hour)
    when :week then t.to_date.beginning_of_week.iso8601
    when :month then t.to_date.beginning_of_month.iso8601
    else t.to_date.iso8601
    end
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
