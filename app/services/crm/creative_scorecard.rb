# 🎯 Placar de UM criativo (item 287). Rodada 3: a régua é a MÉDIA DA CONTA
# ("vamos buscar sempre superar a média") e o alvo é o RECORDE DA CONTA
# ("pra gente ir buscar"). Cada indicador sai com três números — este anúncio,
# a média da conta no mesmo período e o recorde da conta em todo o histórico —
# mais o veredito (acima / na média / abaixo) e o quanto falta para o recorde.
#
# De onde vem: as taxas do anúncio e as médias da conta (Crm::AdMetrics) e o
# melhor anúncio da conta em cada indicador (Crm::CreativeRecords#ad_records,
# com volume mínimo para o recorde não ser acaso de anúncio pequeno).
#
# Teia (0 a 100): a borda de fora (100) é o recorde da conta; este anúncio e a
# média aparecem como fração do recorde. Os parâmetros bom/atenção/ruim
# (Crm::CreativeTargets) continuam valendo nas outras telas — aqui não entram.
class Crm::CreativeScorecard
  INDICATORS = [
    { key: 'hook_rate', label: 'Gancho', metric: 'taxa de parada',
      hint: 'de cada 100 vezes que o anúncio apareceu, quantas pararam para ver 3 segundos' },
    { key: 'hold_rate', label: 'Corpo', metric: 'retenção',
      hint: 'de quem passou dos 3 segundos, quantos viram o vídeo quase todo' },
    { key: 'link_ctr', label: 'CTA', metric: 'CTR de link', digits: 2,
      hint: 'de cada 100 vezes que o anúncio apareceu, quantas viraram clique' },
    { key: 'conv_rate', label: 'Conversa', metric: 'por clique',
      hint: 'de cada 100 cliques, quantos viraram conversa no WhatsApp' },
    { key: 'cost_conversation', label: 'Custo por conversa', metric: 'investido ÷ conversas', money: true, lower: true,
      hint: 'quanto custou, em média, cada conversa iniciada (aqui, menor é melhor)' }
  ].freeze
  RADAR = [%w[hook_rate Gancho], %w[hold_rate Corpo], %w[link_ctr CTA], %w[conv_rate Conversa], %w[booking_rate Agendamento]].freeze
  NEAR = 0.05 # dentro de ±5 % da média = "na média"
  VERDICTS = {
    above: { tone: 'good', label: 'acima da média', money_label: 'mais barato que a média' },
    even: { tone: 'even', label: 'na média', money_label: 'na média' },
    below: { tone: 'bad', label: 'abaixo da média', money_label: 'mais caro que a média' }
  }.freeze
  RADAR_NOTE = 'A borda de fora é o recorde da conta em cada ponta (100). A figura cheia é este anúncio e a tracejada é a média ' \
               'da conta no mesmo período: quanto mais perto da borda, mais perto do recorde.'.freeze
  IS_RECORD = '🏆 este anúncio é o recorde da conta'.freeze

  def initialize(rates:, averages:, records: {}, ad_id: nil)
    @rates = (rates || {}).stringify_keys
    @averages = (averages || {}).stringify_keys
    @records = (records || {}).deep_stringify_keys
    @ad_id = ad_id.to_s
  end

  def call
    { indicators: indicators, radar: { axes: radar_axes, note: RADAR_NOTE } }
  end

  # leitura em frases curtas só com MÉDIA e RECORDE (a página pública usa esta);
  # money: false deixa de fora o custo (versão sem dados financeiros)
  def reading(money: true)
    list = indicators.select { |i| money || !i[:money] }
    return nil if list.empty?

    [group_sentence(list, 'good', 'Supera a média da conta em'), group_sentence(list, 'even', 'Está na média da conta em'),
     group_sentence(list, 'bad', 'Fica atrás da média da conta em'), record_sentence(list), chase_sentence(list)].compact.join(' ')
  end

  private

  def group_sentence(list, tone, opening)
    names = list.select { |i| i[:verdict] == tone }.map { |i| "#{name_of(i)} (#{i[:value_text]} contra #{i[:avg_text]})" }
    names.any? ? "#{opening} #{sentence(names)}." : nil
  end

  def record_sentence(list)
    names = list.select { |i| i[:is_record] }.map { |i| name_of(i) }
    names.any? ? "🏆 É o recorde da conta em #{sentence(names)}." : nil
  end

  def name_of(indicator)
    indicator[:label] == 'CTA' ? 'CTA' : indicator[:label].downcase
  end

  def sentence(names)
    names.to_sentence(words_connector: ', ', two_words_connector: ' e ', last_word_connector: ' e ')
  end

  # o indicador mais longe do recorde, em proporção: é onde há mais para buscar
  def chase_sentence(list)
    far = list.reject { |i| i[:is_record] || i[:record].nil? || i[:record].zero? }
              .max_by { |i| i[:lower] ? (i[:value] - i[:record]) / i[:value] : (i[:record] - i[:value]) / i[:record] }
    far && "Onde há mais para buscar: #{name_of(far)} — #{far[:record_phrase]} (#{far[:record_text]}, #{far[:record_ad]})."
  end

  # ── indicadores ───────────────────────────────────────────────────────────
  def indicators
    INDICATORS.filter_map do |definition|
      value = @rates[definition[:key]]
      next if value.nil?

      indicator(definition, value.to_f)
    end
  end

  def indicator(definition, value)
    avg = @averages[definition[:key]]&.to_f
    money = definition[:money] == true
    lower = definition[:lower] == true
    digits = definition[:digits] || 1
    verdict = verdict_for(value, avg, lower)
    definition.slice(:key, :label, :metric, :hint).merge(
      money: money, digits: digits, lower: lower, value: value, avg: avg,
      value_text: text(value, money, digits), avg_text: avg && text(avg, money, digits),
      verdict: verdict && VERDICTS[verdict][:tone], verdict_label: verdict && VERDICTS[verdict][money ? :money_label : :label],
      phrase: phrase(value, avg, money, digits)
    ).merge(record_fields(definition[:key], value, money, digits, lower))
  end

  # acima / na média / abaixo — no custo é invertido (menor é melhor)
  def verdict_for(value, avg, lower)
    return nil if avg.nil? || !avg.positive?

    ratio = value / avg
    return :even if (ratio - 1).abs <= NEAR

    better = lower ? ratio < 1 : ratio > 1
    better ? :above : :below
  end

  # "3,4 pontos abaixo da média da conta" · "R$ 1,20 acima da média da conta"
  def phrase(value, avg, money, digits = 1)
    return 'sem média da conta para comparar' if avg.nil? || avg.zero?

    diff = value - avg
    return 'igual à média da conta' if diff.abs < (money ? 0.005 : 0.0005)

    "#{gap_text(diff.abs, money, digits)} #{diff.positive? ? 'acima' : 'abaixo'} da média da conta"
  end

  # ── recorde da conta ─────────────────────────────────────────────────────
  def record_fields(key, value, money, digits, lower)
    record = @records[key]
    if record.nil?
      return { record: nil, record_text: nil, record_ad: nil, record_when: nil, is_record: false,
               record_phrase: 'a conta ainda não tem recorde com volume suficiente' }
    end

    best = record['value'].to_f
    mine = holder?(record, value, best, lower)
    { record: best, record_text: text(best, money, digits), record_ad: record['ad_name'], record_when: when_label(record),
      is_record: mine, record_phrase: mine ? IS_RECORD : "#{missing(value, best, money, digits)} para o recorde" }
  end

  def holder?(record, value, best, lower)
    return true if @ad_id.present? && record['ad_id'].to_s == @ad_id

    lower ? value <= best : value >= best
  end

  def missing(value, best, money, digits)
    gap = (value - best).abs
    plural = money || (gap * 100).round(digits) != 1
    "#{plural ? 'faltam' : 'falta'} #{gap_text(gap, money, digits)}"
  end

  def when_label(record)
    since = record['since'].to_s.to_date
    until_date = record['until'].to_s.to_date
    return nil if since.nil? || until_date.nil?

    since == until_date ? "em #{since.strftime('%d/%m/%Y')}" : "de #{since.strftime('%d/%m/%Y')} a #{until_date.strftime('%d/%m/%Y')}"
  rescue Date::Error
    nil
  end

  # ── teia: este anúncio × média × recorde (recorde = borda de fora) ───────
  def radar_axes
    RADAR.filter_map do |key, label|
      value = @rates[key]
      next if value.nil?

      radar_axis(key, label, value.to_f)
    end
  end

  def radar_axis(key, label, value) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    avg = @averages[key]&.to_f
    record = @records.dig(key, 'value')&.to_f
    edge = [record, value, avg].compact.max.to_f
    digits = key == 'link_ctr' ? 2 : 1
    mine = record.present? && holder?(@records[key], value, record, false)
    { key: key, label: label, score: share(value, edge), avg_score: avg && share(avg, edge), record_score: record ? 100 : nil,
      value_text: text(value, false, digits), avg_text: avg && text(avg, false, digits),
      record_text: record && text([record, value].max, false, digits),
      record_ad: record && !mine ? @records.dig(key, 'ad_name') : nil, is_record: mine }
  end

  def share(value, edge)
    edge.positive? ? (value / edge * 100).round.clamp(0, 100) : 0
  end

  # ── formatação pt-BR ─────────────────────────────────────────────────────
  def gap_text(gap, money, digits)
    return money_text(gap) if money

    points = (gap * 100).round(digits)
    "#{decimal(points)} #{points == 1 ? 'ponto' : 'pontos'}"
  end

  def text(value, money, digits)
    money ? money_text(value) : "#{format("%.#{digits}f", value * 100).tr('.', ',')}%"
  end

  def money_text(value)
    whole, cents = format('%.2f', value.to_f).split('.')
    "R$ #{whole.reverse.scan(/\d{1,3}/).join('.').reverse},#{cents}"
  end

  def decimal(value)
    (value % 1).zero? ? value.to_i.to_s : value.to_s.tr('.', ',')
  end
end
