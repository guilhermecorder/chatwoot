# Cesto de indicadores do Meu Painel (item 141): os números-base de um
# período com SÉRIE (dia / semana / mês, conforme o tamanho do período) e o
# PERÍODO ANTERIOR de mesmo tamanho para comparação. Alimenta os gráficos
# dos popups dos cards, os cards criados pelo admin no "+" e as FÓRMULAS
# ("appointments_booked / new_leads" = taxa de agendamento).
#
# Fontes: LeadsUniverse (leads), conversas, tarefas da Agenda (consultas e
# cirurgias) e o histórico de passagem pelas colunas (stage_logs), que é o
# mesmo que alimenta o PRO MAX — os números batem entre telas.
class Crm::KpiBagService
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  MESES_PT = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze

  # granularity: opcional (item 144) — a mini-régua do popup pode forçar o
  # balde; sem ela vale o automático pelo tamanho do período
  def initialize(account:, since:, until_at:, granularity: nil)
    @account = account
    @since = since
    @until_at = until_at
    forced = granularity.to_s.to_sym
    @granularity = %i[day week month].include?(forced) ? forced : pick_granularity
  end

  def call
    prev_until = @since - 1.second
    prev_since = prev_until - (@until_at - @since)
    keys = bucket_keys(@since, @until_at)
    # baldes do período ANTERIOR (item 144): a série sobreposta no gráfico
    # compara balde a balde, não só a média
    prev_keys = bucket_keys(prev_since, prev_until)
    {
      granularity: @granularity,
      points: keys.map { |k, label| { key: k, label: label } },
      prev_points: prev_keys.map { |k, label| { key: k, label: label } },
      previous_label: "#{prev_since.strftime('%d/%m')}–#{prev_until.strftime('%d/%m')}",
      metrics: base_metrics(@since, @until_at, prev_since, prev_until, keys.map(&:first), prev_keys.map(&:first))
    }
  end

  private

  # ── catálogo ──────────────────────────────────────────────────────────
  def base_metrics(since, until_at, prev_since, prev_until, keys, prev_keys) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
    metrics = {}
    add = lambda do |key, label, unit, cur_scope, prev_scope, column, sum: nil|
      series = bucketize(cur_scope, column, sum: sum)
      prev_series = bucketize(prev_scope, column, sum: sum)
      metrics[key] = {
        label: label,
        unit: unit,
        value: total_of(cur_scope, sum: sum),
        prev: total_of(prev_scope, sum: sum),
        series: keys.map { |k| (series[k] || 0).to_f.round(2) },
        prev_series: prev_keys.map { |k| (prev_series[k] || 0).to_f.round(2) }
      }
    end

    add.call('new_leads', 'Novos contatos (leads)', 'n',
             Crm::LeadsUniverse.scope(@account, since, until_at),
             Crm::LeadsUniverse.scope(@account, prev_since, prev_until), 'contacts.created_at')
    add.call('new_conversations', 'Novas conversas', 'n',
             @account.conversations.where(created_at: since..until_at),
             @account.conversations.where(created_at: prev_since..prev_until), 'conversations.created_at')
    add.call('appointments_booked', 'Consultas agendadas (registradas)', 'n',
             booked(since, until_at), booked(prev_since, prev_until), 'tasks.created_at')
    add.call('appointments_due', 'Consultas do período (pela data)', 'n',
             due_tasks('consulta', since, until_at), due_tasks('consulta', prev_since, prev_until), 'tasks.due_at')
    add.call('indications', 'Indicações de cirurgia (consultas)', 'n',
             indicated(since, until_at), indicated(prev_since, prev_until), 'tasks.due_at')
    add.call('appointments_attended', 'Consultas com presença', 'n',
             attendance('consulta', 'attended', since, until_at), attendance('consulta', 'attended', prev_since, prev_until), 'tasks.due_at')
    add.call('appointments_missed', 'Faltas em consultas', 'n',
             attendance('consulta', 'missed', since, until_at), attendance('consulta', 'missed', prev_since, prev_until), 'tasks.due_at')
    add.call('surgeries_booked', 'Cirurgias agendadas (registradas)', 'n',
             created_tasks('cirurgia', since, until_at), created_tasks('cirurgia', prev_since, prev_until), 'tasks.created_at')
    add.call('surgeries_done', 'Cirurgias realizadas (Agenda)', 'n',
             attendance('cirurgia', 'attended', since, until_at), attendance('cirurgia', 'attended', prev_since, prev_until), 'tasks.due_at')
    add.call('surgeries_missed', 'Cirurgias — não vieram', 'n',
             attendance('cirurgia', 'missed', since, until_at), attendance('cirurgia', 'missed', prev_since, prev_until), 'tasks.due_at')

    # passagem pelas colunas do funil + faturamento (mesma fonte do PRO MAX)
    pipeline = @account.crm_pipelines.order(:id).first
    if pipeline
      pipeline.stages.order(:position).each do |stage|
        add.call("stage_#{stage.id}", "Entrou em #{stage.name}", 'n',
                 stage_entries(pipeline, stage.id, since, until_at),
                 stage_entries(pipeline, stage.id, prev_since, prev_until), 'crm_contact_stage_logs.entered_at')
      end
      add.call('revenue', 'Faturamento fechado (R$)', 'brl',
               revenue_logs(pipeline, since, until_at), revenue_logs(pipeline, prev_since, prev_until),
               'crm_contact_stage_logs.entered_at', sum: 'COALESCE(crm_contacts.value, 0)')
    end
    metrics
  end

  # ── escopos ───────────────────────────────────────────────────────────
  def booked(since, until_at)
    @account.tasks.where(task_type: 'consulta', created_at: since..until_at)
            .where('tasks.due_at IS NULL OR tasks.due_at >= tasks.created_at')
  end

  def created_tasks(type, since, until_at)
    @account.tasks.where(task_type: type, created_at: since..until_at)
  end

  def due_tasks(type, since, until_at)
    @account.tasks.where(task_type: type, canceled_at: nil, due_at: since..until_at)
  end

  def indicated(since, until_at)
    due_tasks('consulta', since, until_at).where(surgery_indication: 'indicated')
  end

  def attendance(type, status, since, until_at)
    @account.tasks.where(task_type: type, attendance: status, canceled_at: nil, due_at: since..until_at)
  end

  def stage_entries(pipeline, stage_id, since, until_at)
    Crm::StageLog.joins(:crm_contact)
                 .where(crm_contacts: { pipeline_id: pipeline.id }, stage_id: stage_id, entered_at: since..until_at)
  end

  def revenue_logs(pipeline, since, until_at)
    Crm::StageLog.joins(:crm_contact)
                 .where(crm_contacts: { pipeline_id: pipeline.id }, entered_at: since..until_at)
                 .where("crm_contact_stage_logs.stage_name ILIKE '%cirurgia realizada%'")
  end

  # ── baldes ────────────────────────────────────────────────────────────
  def pick_granularity
    days = ((@until_at.to_date - @since.to_date).to_i + 1)
    return :day if days <= 45
    return :week if days <= 400

    :month
  end

  def bucket_sql(column)
    tz_col = "#{column} AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo'"
    case @granularity
    when :week then "to_char(date_trunc('week', #{tz_col}), 'YYYY-MM-DD')"
    when :month then "to_char(date_trunc('month', #{tz_col}), 'YYYY-MM-DD')"
    else "to_char(#{tz_col}, 'YYYY-MM-DD')"
    end
  end

  def bucket_keys(since, until_at)
    keys = []
    case @granularity
    when :week
      d = since.to_date.beginning_of_week
      while d <= until_at.to_date
        keys << [d.iso8601, d.strftime('%d/%m')]
        d += 7
      end
    when :month
      d = since.to_date.beginning_of_month
      while d <= until_at.to_date
        keys << [d.iso8601, "#{MESES_PT[d.month - 1]}/#{d.strftime('%y')}"]
        d = d.next_month
      end
    else
      (since.to_date..until_at.to_date).each { |d| keys << [d.iso8601, d.strftime('%d/%m')] }
    end
    keys
  end

  def bucketize(scope, column, sum: nil)
    grouped = scope.reorder(nil).group(Arel.sql(bucket_sql(column)))
    sum ? grouped.sum(Arel.sql(sum)) : grouped.count
  end

  def total_of(scope, sum: nil)
    sum ? scope.reorder(nil).sum(Arel.sql(sum)).to_f.round(2) : scope.reorder(nil).count
  end
end
