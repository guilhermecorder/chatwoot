# Dashboard da AGENDA (análise do gestor): tudo que importa sobre a agenda
# num lugar só — volume de consultas, comparecimento, faltas, cancelamentos,
# reagendamentos, conferência pendente, mix por modalidade (avaliação/
# retorno/exames), por médico, por unidade, por dia da semana, e o trilho
# de cirurgias (realizadas, não veio, veio-e-não-fez, por clínica).
# Ocupação % (agenda cheia/aproveitamento) é calculada na tela, com as
# mesmas janelas da Agenda/Meu Painel.
class Api::V1::Accounts::Crm::AgendaDashboardsController < Api::V1::Accounts::BaseController
  # LIBERADO PARA A EQUIPE (item 86): dado operacional da agenda, sem
  # valores financeiros — todo o time acompanha comparecimento e ocupação.
  include Crm::ResolvesPeriod

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    since, until_at = resolve_range

    render json: {
      period: params[:preset].presence || 'month',
      consultas: consultas_kpis(since, until_at),
      by_modality: by_modality(since, until_at),
      by_doctor: by_doctor(since, until_at),
      by_unit: by_unit(since, until_at),
      by_weekday: by_weekday(since, until_at),
      cirurgias: cirurgias_kpis(since, until_at),
      upcoming: upcoming_stats
    }
  end

  private

  def account
    Current.account
  end


  def resolve_range
    # régua padrão CEVICO (06/08) resolve primeiro; presets antigos seguem
    # abaixo. AGENDA olha para a FRENTE: em "Este mês"/"Este ano" o fim do
    # período vai até o fim do calendário (a consulta de amanhã conta).
    if (range = standard_period_range)
      now = TZ.now
      since, until_at = range
      until_at = now.end_of_month if params[:preset] == 'month'
      until_at = now.end_of_year if params[:preset] == 'year'
      return [since, until_at]
    end

    now = TZ.now
    case params[:preset]
    when 'week'  then [now.beginning_of_week.beginning_of_day, now.end_of_week.end_of_day]
    when 'all'   then [Time.zone.at(0), now.end_of_day]
    when 'last_month' then [now.last_month.beginning_of_month, now.last_month.end_of_month]
    else [now.beginning_of_month.beginning_of_day, now.end_of_month.end_of_day]
    end
  end

  # consultas do período (canceladas ficam FORA das contas, mas são contadas)
  def consultas(since, until_at)
    account.tasks.where(task_type: 'consulta', canceled_at: nil, due_at: since..until_at)
  end

  def cirurgias(since, until_at)
    account.tasks.where(task_type: 'cirurgia', canceled_at: nil, due_at: since..until_at)
  end

  def consultas_kpis(since, until_at)
    scope = consultas(since, until_at)
    attended = scope.where(attendance: 'attended').count
    missed = scope.where(attendance: 'missed').count
    canceled = account.tasks.where(task_type: 'consulta', due_at: since..until_at)
                      .where.not(canceled_at: nil).count
    indicated = scope.where(surgery_indication: 'indicated').count
    # passadas sem ✓/✗ = conferência pendente (buraco operacional)
    unconfirmed = scope.where(attendance: nil).where('due_at <= ?', Time.current).count

    {
      total: scope.count,
      attended: attended,
      missed: missed,
      show_rate: pct(attended, attended + missed),
      canceled: canceled,
      rescheduled: scope.where('rescheduled_count > 0').count,
      unconfirmed: unconfirmed,
      indications: indicated,
      indication_rate: pct(indicated, attended)
    }
  end

  MODALITY_LABELS = { 'avaliacao' => 'Avaliação', 'retorno' => 'Retorno', 'exames' => 'Exames' }.freeze

  def by_modality(since, until_at)
    scope = consultas(since, until_at)
    total = scope.count
    scope.group(:modality).count.map do |mod, count|
      key = mod.presence || 'avaliacao' # consulta antiga sem tipo = avaliação
      m_scope = mod.nil? ? scope.where(modality: [nil, key]) : scope.where(modality: mod)
      attended = m_scope.where(attendance: 'attended').count
      missed = m_scope.where(attendance: 'missed').count
      {
        key: key,
        label: MODALITY_LABELS[key] || key,
        count: count,
        share: pct(count, total),
        show_rate: pct(attended, attended + missed)
      }
    end.group_by { |m| m[:key] }.map do |key, rows| # nil e 'avaliacao' agregados
      first = rows.first
      count = rows.sum { |r| r[:count] }
      first.merge(count: count, share: pct(count, total))
    end.sort_by { |m| -m[:count] }
  end

  def by_doctor(since, until_at)
    scope = consultas(since, until_at).where.not(doctor: [nil, ''])
    variants = scope.distinct.pluck(:doctor).group_by { |raw| Crm::DoctorNames.canonical(raw, account: Current.account) }
    variants.delete(nil)

    variants.map do |doc, raw_names|
      d = scope.where(doctor: raw_names)
      attended = d.where(attendance: 'attended').count
      missed = d.where(attendance: 'missed').count
      {
        doctor: doc,
        count: d.count,
        attended: attended,
        missed: missed,
        show_rate: pct(attended, attended + missed),
        indications: d.where(surgery_indication: 'indicated').count
      }
    end.sort_by { |r| -r[:count] }
  end

  # nomes das unidades: conta (Personalização) > segmento
  def unit_labels
    Crm::SegmentoConta.unit_labels(Current.account)
  end

  def by_unit(since, until_at)
    scope = consultas(since, until_at)
    scope.group(:unit).count.map do |unit, count|
      u = scope.where(unit: unit)
      attended = u.where(attendance: 'attended').count
      missed = u.where(attendance: 'missed').count
      {
        key: unit.presence || 'sem_unidade',
        label: unit_labels[unit] || unit.presence || 'Sem unidade',
        count: count,
        attended: attended,
        missed: missed,
        show_rate: pct(attended, attended + missed)
      }
    end.sort_by { |u| -u[:count] }
  end

  WEEKDAYS = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado].freeze

  def by_weekday(since, until_at)
    counts = consultas(since, until_at)
             .group("EXTRACT(DOW FROM due_at AT TIME ZONE 'America/Sao_Paulo')").count
    (1..5).map do |dow| # seg-sex (fim de semana é bloqueado na agenda)
      { dow: dow, label: WEEKDAYS[dow], count: counts[dow.to_f] || counts[dow] || 0 }
    end
  end

  def cirurgias_kpis(since, until_at)
    scope = cirurgias(since, until_at)
    done = scope.where(attendance: 'attended').or(scope.where(status: :done)).count
    locations = CrmSetting.find_by(account: account)&.agenda_config&.dig('surgery_locations') || []
    labels = locations.to_h { |l| [l['key'], l['label']] }

    {
      total: scope.count,
      done: done,
      missed: scope.where(attendance: 'missed').count,
      attended_not_done: scope.where(attendance: 'attended_not_done').count,
      by_location: scope.group(:unit).count.map do |unit, count|
        { key: unit.presence || 'sem_local', label: labels[unit] || unit.presence || 'Sem local', count: count }
      end.sort_by { |l| -l[:count] }
    }
  end

  # independente do período: o que vem pela frente
  def upcoming_stats
    now = Time.current
    {
      consultas_next7: account.tasks.where(task_type: 'consulta', canceled_at: nil, due_at: now..7.days.from_now).count,
      cirurgias_next7: account.tasks.where(task_type: 'cirurgia', canceled_at: nil, due_at: now..7.days.from_now).count,
      unconfirmed_past: account.tasks.where(task_type: %w[consulta cirurgia], canceled_at: nil, attendance: nil)
                               .where(due_at: 30.days.ago..now).count
    }
  end

  def pct(part, total)
    total.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end
end
