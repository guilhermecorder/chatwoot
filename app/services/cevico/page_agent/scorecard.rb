# 🎯 PLACAR de UMA página (item 353) — a tecnologia da Central de Criativos
# nas páginas: cada taxa sai com três números — esta página, a média da casa
# no período e o recorde da casa — mais o veredito (acima / na média / abaixo)
# e quanto falta para o recorde. A teia (0 a 100) tem o recorde na borda.
# Mesmo formato de saída do Crm::CreativeScorecard: a tela reaproveita as peças.
class Cevico::PageAgent::Scorecard
  INDICATORS = [
    { key: 'google', label: 'Título no Google', metric: 'clique por aparição', digits: 1,
      hint: 'de cada 100 vezes que a página apareceu na busca, quantas viraram clique (Search Console, 28 dias)' },
    { key: 'reading', label: 'Leitura', metric: 'leram até a metade', hint: 'de cada 100 visitas, quantas passaram da metade da página' },
    { key: 'cta', label: 'Convite', metric: 'clique no WhatsApp por visita', hint: 'de cada 100 visitas, quantas tocaram no WhatsApp' },
    { key: 'arrival', label: 'Chegada', metric: 'lead por clique', hint: 'de cada 100 cliques, quantos chegaram na caixa com o Protocolo' },
    { key: 'booking', label: 'Agenda', metric: 'agendou por lead', hint: 'de cada 100 leads desta página, quantos marcaram consulta' },
    { key: 'result', label: 'Resultado', metric: 'lead por visita', hint: 'de cada 100 visitas, quantas viraram lead — a página inteira' }
  ].freeze
  RADAR = [%w[google Google], %w[reading Leitura], %w[cta Convite], %w[arrival Chegada], %w[booking Agenda]].freeze
  NEAR = 0.05
  VERDICTS = { above: { tone: 'good', label: 'acima da média da casa' }, even: { tone: 'even', label: 'na média da casa' },
               below: { tone: 'bad', label: 'abaixo da média da casa' } }.freeze
  RADAR_NOTE = 'A borda de fora é o recorde da casa em cada ponta (100). A figura cheia é esta página e a tracejada é a média ' \
               'das páginas no mesmo período: quanto mais perto da borda, mais perto do recorde.'.freeze
  IS_RECORD = '🏆 esta página é o recorde da casa'.freeze

  def initialize(rates:, averages:, records: {}, page_id: nil)
    @rates = (rates || {}).stringify_keys
    @averages = (averages || {}).stringify_keys
    @records = (records || {}).deep_stringify_keys
    @page_id = page_id
  end

  def call
    { indicators: indicators, radar: { axes: radar_axes, note: RADAR_NOTE }, reading: reading }
  end

  # frases curtas: o que supera, o que está na média, o que fica atrás, o recorde e onde buscar
  def reading
    list = indicators
    return nil if list.empty?

    [group(list, 'good', 'Supera a média da casa em'), group(list, 'even', 'Está na média da casa em'),
     group(list, 'bad', 'Fica atrás da média da casa em'), record_sentence(list), chase_sentence(list)].compact.join(' ')
  end

  private

  def group(list, tone, opening)
    names = list.select { |i| i[:verdict] == tone }.map { |i| "#{i[:label].downcase} (#{i[:value_text]} contra #{i[:avg_text]})" }
    names.any? ? "#{opening} #{sentence(names)}." : nil
  end

  def record_sentence(list)
    names = list.select { |i| i[:is_record] }.map { |i| i[:label].downcase }
    names.any? ? "🏆 É o recorde da casa em #{sentence(names)}." : nil
  end

  def chase_sentence(list)
    far = list.reject { |i| i[:is_record] || i[:record].nil? || i[:record].zero? }.max_by { |i| (i[:record] - i[:value]) / i[:record] }
    far && "Onde há mais para buscar: #{far[:label].downcase} — #{far[:record_phrase]} (#{far[:record_text]}, #{far[:record_ad]})."
  end

  def sentence(names)
    names.to_sentence(words_connector: ', ', two_words_connector: ' e ', last_word_connector: ' e ')
  end

  def indicators
    @indicators ||= INDICATORS.filter_map do |definition|
      value = @rates[definition[:key]]
      next if value.nil?

      indicator(definition, value.to_f)
    end
  end

  def indicator(definition, value)
    avg = @averages[definition[:key]]&.to_f
    digits = definition[:digits] || 1
    verdict = verdict_for(value, avg)
    definition.slice(:key, :label, :metric, :hint).merge(
      money: false, digits: digits, lower: false, value: value, avg: avg,
      value_text: text(value, digits), avg_text: avg && text(avg, digits),
      verdict: verdict && VERDICTS[verdict][:tone], verdict_label: verdict && VERDICTS[verdict][:label],
      phrase: phrase(value, avg, digits)
    ).merge(record_fields(definition[:key], value, digits))
  end

  def verdict_for(value, avg)
    return nil if avg.nil? || !avg.positive?

    ratio = value / avg
    return :even if (ratio - 1).abs <= NEAR

    ratio > 1 ? :above : :below
  end

  def phrase(value, avg, digits)
    return 'sem média da casa para comparar' if avg.nil? || avg.zero?

    diff = value - avg
    return 'igual à média da casa' if diff.abs < 0.0005

    "#{gap_text(diff.abs, digits)} #{diff.positive? ? 'acima' : 'abaixo'} da média da casa"
  end

  def record_fields(key, value, digits)
    record = @records[key]
    if record.nil?
      return { record: nil, record_text: nil, record_ad: nil, record_when: nil, is_record: false,
               record_phrase: 'a casa ainda não tem recorde com volume suficiente' }
    end

    best = record['value'].to_f
    mine = (@page_id.present? && record['page_id'].to_s == @page_id.to_s) || value >= best
    { record: best, record_text: text(best, digits), record_ad: "#{record['emoji']} #{record['page_title']}".strip,
      record_when: when_label(record), is_record: mine,
      record_phrase: mine ? IS_RECORD : "#{missing(value, best, digits)} para o recorde" }
  end

  def missing(value, best, digits)
    gap = (best - value).abs
    "#{(gap * 100).round(digits) == 1 ? 'falta' : 'faltam'} #{gap_text(gap, digits)}"
  end

  def when_label(record)
    since = record['since'].to_s.to_date
    until_date = record['until'].to_s.to_date
    "de #{since.strftime('%d/%m/%Y')} a #{until_date.strftime('%d/%m/%Y')}"
  rescue Date::Error
    nil
  end

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
    mine = record.present? && ((@page_id.present? && @records.dig(key, 'page_id').to_s == @page_id.to_s) || value >= record)
    { key: key, label: label, score: share(value, edge), avg_score: avg && share(avg, edge), record_score: record ? 100 : nil,
      value_text: text(value, 1), avg_text: avg && text(avg, 1), record_text: record && text([record, value].max, 1),
      record_ad: record && !mine ? @records.dig(key, 'page_title') : nil, is_record: mine }
  end

  def share(value, edge)
    edge.positive? ? (value / edge * 100).round.clamp(0, 100) : 0
  end

  def gap_text(gap, digits)
    points = (gap * 100).round(digits)
    "#{decimal(points)} #{points == 1 ? 'ponto' : 'pontos'}"
  end

  def text(value, digits)
    "#{format("%.#{digits}f", value * 100).tr('.', ',')}%"
  end

  def decimal(value)
    (value % 1).zero? ? value.to_i.to_s : value.to_s.tr('.', ',')
  end
end
