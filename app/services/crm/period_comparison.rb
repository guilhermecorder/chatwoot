# 📐 item 394 (11/11) — BASE DE COMPARAÇÃO: o ponto ÚNICO do servidor que diz
# "comparar este período com qual outro?". Pedido do Guilherme: "é bom a gente
# sempre poder ter uma base de comparação, por exemplo, comparar com a semana
# passada, o mês passado, um mês com o outro".
#
#   previous  o período de MESMO TAMANHO logo antes (padrão — o de sempre):
#             hoje × ontem, 7 dias × 7 dias anteriores, semana × semana anterior.
#             Mês fechado compara com o mês fechado anterior (outubro × setembro).
#   month     o MESMO trecho um mês antes (1–11/11 × 1–11/10)
#   pick      o MESMO trecho num mês escolhido (compare_month=AAAA-MM)
#
# Uso no controller (Crm::ResolvesPeriod):
#   compare = period_comparison(since, until_at)
#   compare.since / compare.until_at   → o intervalo a comparar
#   compare.label                      → "ontem", "setembro", "mesmo período de outubro"
#   compare.to_h                       → o que a tela precisa para escrever "vs …"
class Crm::PeriodComparison
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  MODES = %w[previous month pick].freeze
  MESES = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze
  PREVIOUS_LABELS = { 'today' => 'ontem', 'yesterday' => 'anteontem', 'last7' => '7 dias anteriores',
                      'last_week' => 'semana anterior', 'last90' => '90 dias anteriores' }.freeze

  attr_reader :since, :until_at, :mode

  def self.from_params(since, until_at, params)
    new(since, until_at, mode: params[:compare], month: params[:compare_month], preset: params[:preset])
  end

  def initialize(cur_since, cur_until, mode: nil, month: nil, preset: nil)
    @cur_since = cur_since.in_time_zone(TZ)
    @cur_until = cur_until.in_time_zone(TZ)
    @preset = preset.to_s
    @mode = MODES.include?(mode.to_s) ? mode.to_s : 'previous'
    @months_back = months_back(month)
    # mês escolhido inválido ou igual ao do período: volta para o padrão
    @mode = 'previous' if @mode == 'pick' && @months_back.zero?
    @since, @until_at = range
  end

  # "ontem", "setembro", "mesmo período de outubro" — entra depois de "vs "
  def label
    return previous_label if mode == 'previous'

    return month_name(since) if full_month?
    return "mesmo período de #{month_name(since)}" if same_month?

    # trecho que atravessa meses (90 dias, este ano): não cabe num nome de mês
    return 'um mês antes' if @months_back == 1

    "#{@months_back.abs} meses #{@months_back.positive? ? 'antes' : 'depois'}"
  end

  # "01/10–11/10" (um dia só: "10/11")
  def range_label
    from = since.strftime('%d/%m')
    to = until_at.strftime('%d/%m')
    from == to ? from : "#{from}–#{to}"
  end

  def cache_key
    "#{mode}:#{since.to_i}:#{until_at.to_i}"
  end

  def to_h
    { modo: mode, rotulo: label, datas: range_label, de: since.iso8601, ate: until_at.iso8601 }
  end

  private

  def range
    return shifted(@months_back) unless mode == 'previous'
    return shifted(1) if full_month?

    return previous_days if @cur_since == @cur_since.beginning_of_day

    prev_until = @cur_since - 1.second
    [prev_until - (@cur_until - @cur_since), prev_until]
  end

  # período em dias inteiros (toda a régua padrão): os N dias inteiros de antes
  # — 05/11–11/11 compara com 29/10–04/11, sem escorregar um segundo para 28/10
  def previous_days
    days = (@cur_until.to_date - @cur_since.to_date).to_i + 1
    [@cur_since - days.days, (@cur_since - 1.day).end_of_day]
  end

  # o mesmo trecho N meses antes (N negativo = depois). Mês fechado vira o mês
  # fechado; trecho dentro de um mês não vaza para o mês seguinte (31 × 30 dias)
  def shifted(months)
    return [@cur_since.advance(months: -months).beginning_of_month, @cur_since.advance(months: -months).end_of_month] if full_month?

    from = @cur_since.advance(months: -months)
    to = from + (@cur_until - @cur_since)
    to = from.end_of_month if same_month? && to > from.end_of_month
    [from, to]
  end

  def full_month?
    @cur_since == @cur_since.beginning_of_month && @cur_until.to_date == @cur_since.end_of_month.to_date
  end

  def same_month?
    @cur_since.year == @cur_until.year && @cur_since.month == @cur_until.month
  end

  def months_back(month)
    return 1 unless mode == 'pick'

    match = month.to_s.match(/\A(\d{4})-(\d{1,2})\z/)
    return 0 unless match && (1..12).cover?(match[2].to_i)

    ((@cur_since.year * 12) + @cur_since.month) - ((match[1].to_i * 12) + match[2].to_i)
  end

  def previous_label
    return month_name(since) if full_month?

    PREVIOUS_LABELS[@preset] || 'período anterior'
  end

  def month_name(time)
    name = MESES[time.month - 1]
    time.year == @cur_since.year ? name : "#{name}/#{time.strftime('%y')}"
  end
end
