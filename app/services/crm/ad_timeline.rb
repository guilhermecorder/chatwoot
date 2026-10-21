# 🧭 LINHA DO TEMPO CONVERGENTE de um anúncio (item 299, 30/09; pedido dele:
# "gostaria de ter todo o histórico, de todas as fontes, distribuídos em
# convergência, na linha do tempo — tudo sincronizado"). Coloca no MESMO eixo
# de tempo o que cada fonte sabe sobre o anúncio:
#   Meta          → investimento, exibições, cliques, conversas (por dia)
#   WhatsApp/CRM  → leads que chegaram por este anúncio (data da chegada)
#   CRM + Agenda  → consulta marcada, comparecimento (data em que aconteceu)
#   CRM + Agenda + Oftalmofácil → cirurgia fechada, cirurgia realizada, receita
# Cada passo do paciente entra na data em que ACONTECEU (não na data do lead):
# é isso que mostra o atraso entre investir e colher. `lags` traz a mediana de
# dias entre um passo e o seguinte. Nenhum dado de paciente sai daqui — só contagens.
class Crm::AdTimeline # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  TRACKS = [
    { key: 'spend', label: 'Investimento', source: 'Meta', unit: 'money' },
    { key: 'impressions', label: 'Exibições', source: 'Meta', unit: 'count' },
    { key: 'link_clicks', label: 'Cliques no link', source: 'Meta', unit: 'count' },
    { key: 'conversations', label: 'Conversas iniciadas', source: 'Meta', unit: 'count' },
    { key: 'leads', label: 'Leads', source: 'WhatsApp + CRM', unit: 'count' },
    { key: 'booked', label: 'Consultas marcadas', source: 'CRM + Agenda', unit: 'count' },
    { key: 'attended', label: 'Compareceram', source: 'CRM + Agenda', unit: 'count' },
    { key: 'closed', label: 'Cirurgias fechadas', source: 'CRM + Agenda + Oftalmofácil', unit: 'count' },
    { key: 'surgeries', label: 'Cirurgias realizadas', source: 'CRM + Agenda + Oftalmofácil', unit: 'count' },
    { key: 'revenue', label: 'Receita', source: 'Oftalmofácil + CRM', unit: 'money' }
  ].freeze
  STEPS = %w[leads booked attended closed surgeries].freeze
  STEP_NAMES = { 'leads' => 'chegar', 'booked' => 'marcar a consulta', 'attended' => 'comparecer',
                 'closed' => 'fechar a cirurgia', 'surgeries' => 'operar' }.freeze

  def initialize(account:, ad_id:, since_date:, until_date:, daily: [])
    @account = account
    @ad_id = ad_id.to_s
    @since = since_date.to_date
    @until = [until_date.to_date, TZ.now.to_date].min
    @daily = daily
  end

  def call
    { granularity: granularity, since: @since.iso8601, until: @until.iso8601, buckets: buckets.map { |b| bucket_json(b) },
      tracks: tracks, lags: lags, marks: marks, tracked_since: tracked_since&.iso8601,
      notes: notes }
  end

  private

  # até 45 dias: dia a dia; até 1 ano e meio: semana a semana; depois, mês a mês
  def granularity
    @granularity ||= begin
      span = (@until - @since).to_i
      next_size = span <= 550 ? 'week' : 'month'
      span <= 45 ? 'day' : next_size
    end
  end

  def buckets
    @buckets ||= begin
      list = []
      cursor = bucket_start(@since)
      while cursor <= @until
        list << cursor
        cursor = next_bucket(cursor)
      end
      list
    end
  end

  def bucket_start(date)
    case granularity
    when 'week' then date.beginning_of_week
    when 'month' then date.beginning_of_month
    else date
    end
  end

  def next_bucket(date)
    case granularity
    when 'week' then date + 7
    when 'month' then date.next_month
    else date + 1
    end
  end

  def bucket_json(start)
    finish = [next_bucket(start) - 1, @until].min
    label = granularity == 'month' ? I18n.l(start, format: '%m/%Y') : start.strftime('%d/%m')
    { start: start.iso8601, end: finish.iso8601, label: label }
  end

  def index_of(date)
    return nil if date.nil?

    day = date.respond_to?(:in_time_zone) && !date.is_a?(Date) ? date.in_time_zone(TZ).to_date : date.to_date
    return nil if day < @since || day > @until

    buckets.index(bucket_start(day))
  end

  def empty
    Array.new(buckets.size, 0)
  end

  def tracks
    values = meta_values.merge(step_values)
    TRACKS.map do |track|
      list = values[track[:key]] || empty
      track.merge(values: list.map { |v| track[:unit] == 'money' ? v.to_f.round(2) : v.to_i }, total: round_total(list, track))
    end
  end

  def round_total(list, track)
    track[:unit] == 'money' ? list.sum.to_f.round(2) : list.sum.to_i
  end

  def meta_values
    out = %w[spend impressions link_clicks conversations].index_with { empty }
    @daily.each do |m|
      i = index_of(m['date'])
      next unless i

      out.each_key { |key| out[key][i] += m[key].to_f }
    end
    out
  end

  # { 'leads' => [n por balde], … } + receita na data da cirurgia
  def step_values
    out = STEPS.index_with { empty }.merge('revenue' => empty)
    events.each_value do |dates|
      STEPS.each { |step| (i = index_of(dates[step])) && out[step][i] += 1 }
      (i = index_of(dates['surgeries'])) && out['revenue'][i] += dates['revenue'].to_f
    end
    out
  end

  # { contact_id => { 'leads' => data, 'booked' => data|nil, …, 'revenue' => valor } }
  def events # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    @events ||= begin
      steps = Crm::AdFunnelSteps.new(@account, lead_dates.keys)
      lead_dates.to_h do |id, arrived|
        dates = { 'leads' => arrived }
        dates['surgeries'] = first_date(id, 'surgeries') if steps.surgeries.include?(id)
        dates['closed'] = first_date(id, 'closed', dates['surgeries']) if steps.closed.include?(id)
        dates['attended'] = first_date(id, 'attended', dates['closed']) if steps.attended.include?(id)
        dates['booked'] = first_date(id, 'booked', dates['attended']) if steps.booked.include?(id)
        [id, dates.merge('revenue' => steps.surgeries.include?(id) ? steps.revenue_of(id) : 0)]
      end
    end
  end

  # a primeira data em que o passo aconteceu, em qualquer fonte; um paciente que
  # pulou a etapa no registro (ex.: operou sem "compareceu" marcado) herda a data do passo seguinte
  def first_date(contact_id, step, fallback = nil)
    [stage_dates.dig(step, contact_id), agenda_dates.dig(step, contact_id), hub_dates.dig(step, contact_id), fallback].compact.min
  end

  def lead_dates
    @lead_dates ||= @account.contacts
                            .where("additional_attributes -> 'meta_ads' ->> 'source_id' = ?", @ad_id)
                            .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz >= ?", @since.beginning_of_day)
                            .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz <= ?", @until.end_of_day)
                            .pluck(:id, Arel.sql("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz")).to_h
  end

  # CRM: primeira entrada em qualquer coluna do degrau
  def stage_dates
    @stage_dates ||= Crm::AdFunnelSteps.stage_ids_for(@account).transform_keys(&:to_s).transform_values do |ids|
      next {} if ids.empty? || lead_dates.empty?

      Crm::StageLog.joins(:crm_contact).where(stage_id: ids, crm_contacts: { contact_id: lead_dates.keys })
                   .group('crm_contacts.contact_id').minimum(:entered_at)
    end
  end

  def agenda_dates
    @agenda_dates ||= begin
      tasks = @account.tasks.where(contact_id: lead_dates.keys)
      consult = tasks.where(task_type: 'consulta')
      surgery = tasks.where(task_type: 'cirurgia')
      { 'booked' => consult.group(:contact_id).minimum(:created_at),
        'attended' => consult.where(attendance: 'attended').group(:contact_id).minimum(:due_at),
        'closed' => surgery.where(canceled_at: nil).group(:contact_id).minimum(:created_at),
        'surgeries' => surgery.where(attendance: 'attended').group(:contact_id).minimum(:due_at) }
    end
  end

  def hub_dates
    @hub_dates ||= begin
      scope = Crm::OftalmofacilSurgery.where(account_id: @account.id, contact_id: lead_dates.keys)
      { 'closed' => scope.where(status_kind: Crm::AdFunnelSteps::OF_CLOSED).group(:contact_id)
                         .minimum(Arel.sql('COALESCE(of_created_at, created_at)')),
        'surgeries' => scope.where(status_kind: Crm::AdFunnelSteps::OF_DONE).where(surgery_date: ...Time.zone.today)
                            .group(:contact_id).minimum(:surgery_date) }
    end
  end

  # mediana de dias entre um passo e o seguinte (só de quem deu os dois passos)
  def lags
    STEPS.each_cons(2).filter_map do |from, to|
      days = events.values.filter_map do |d|
        next unless d[from] && d[to]

        [(to_day(d[to]) - to_day(d[from])).to_i, 0].max
      end
      next if days.empty?

      { from: from, to: to, days: median(days), people: days.size, text: lag_text(median(days), from, to) }
    end
  end

  def lag_text(days, from, to)
    between = "entre #{STEP_NAMES[from]} e #{STEP_NAMES[to]}"
    return "no mesmo dia #{between}" if days.zero?

    "#{days} #{days == 1 ? 'dia' : 'dias'} #{between}"
  end

  def to_day(value)
    value.is_a?(Date) ? value : value.in_time_zone(TZ).to_date
  end

  def median(list)
    sorted = list.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
  end

  # marcos no eixo: quando o anúncio começou e parou de gastar
  def marks
    spent = @daily.select { |m| m['spend'].to_f.positive? }.pluck('date').sort
    return [] if spent.empty?

    list = [{ date: spent.first.iso8601, bucket: index_of(spent.first), label: 'entrou no ar' }]
    list << { date: spent.last.iso8601, bucket: index_of(spent.last), label: 'último dia com investimento' } if spent.last < @until - 3
    list
  end

  # desde quando o sistema grava de qual anúncio o lead veio (antes disso a jornada não liga ao anúncio)
  def tracked_since
    @tracked_since ||= begin
      first = @account.contacts.where("additional_attributes -> 'meta_ads' ->> 'captured_at' IS NOT NULL")
                      .minimum(Arel.sql("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz"))
      first&.in_time_zone(TZ)&.to_date
    end
  end

  def notes
    list = []
    if tracked_since && tracked_since > @since
      list << "A ligação entre paciente e anúncio começou a ser gravada em #{tracked_since.strftime('%d/%m/%Y')}: antes disso " \
              'aparecem os números da Meta, mas não a jornada dos pacientes.'
    end
    list << 'Cada passo entra na data em que aconteceu. Por isso a cirurgia aparece semanas depois do investimento que a trouxe.'
    list
  end
end
