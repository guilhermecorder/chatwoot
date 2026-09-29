# 🥇 "Os MAIS e os MENOS" de uma quebra do anúncio (item 287, rodada 3):
# onde apareceu (posicionamento) e quem viu (idade × sexo).
#
# De onde vem: as linhas da quebra que a Meta devolve (Crm::AdBreakdownService).
# Como se ramifica: cada linha ganha duas taxas — cliques a cada 100 exibições
# e conversas a cada 100 cliques — e o APROVEITAMENTO, que é o caminho inteiro:
# conversas a cada 1.000 exibições.
# Para onde vai: selo de "mais/menos conversas" (volume) e de "melhor/pior
# aproveitamento" (eficiência), mais uma frase-resumo.
#
# Regras para não premiar acaso: linha com menos de MIN_IMPRESSIONS não disputa
# aproveitamento; só há vencedor quando ele é ÚNICO (o segundo colocado fica
# mais de TIE de distância); e, no aproveitamento, a distância tem de ser maior
# que a oscilação normal de um número pequeno (1 ÷ raiz das conversas: com 9
# conversas, 33 %; com 100, 10 %). Tudo igual → "não há diferença relevante".
class Crm::BreakdownHighlights
  MIN_IMPRESSIONS = 100
  TIE = 0.02
  MAX_ROWS = 12
  BADGES = {
    most: { label: 'mais conversas', tone: 'good' }, least: { label: 'menos conversas', tone: 'bad' },
    best: { label: 'melhor aproveitamento', tone: 'good' }, worst: { label: 'pior aproveitamento', tone: 'bad' }
  }.freeze
  PLACES = { 'placement' => %w[em posicionamentos], 'audience' => %w[com faixas] }.freeze

  def initialize(rows, kind: 'placement')
    @rows = Array(rows).map { |row| row.to_h.symbolize_keys }
    @kind = PLACES.key?(kind.to_s) ? kind.to_s : 'placement'
  end

  def call
    list = ranked
    picks = { most: unique_edge(list, :conversations, :max), least: unique_edge(list, :conversations, :min),
              best: unique_edge(eligible(list), :yield_1000, :max, noise: true),
              worst: unique_edge(eligible(list), :yield_1000, :min, noise: true) }
    picks[:least] = nil if picks[:least] && picks[:least] == picks[:most]
    picks[:worst] = nil if picks[:worst] && picks[:worst] == picks[:best]
    { rows: list.map { |row| row.merge(badges: badges_for(row, picks)) }, summary: summary(list, picks),
      no_difference: picks.values.compact.empty?, min_impressions: MIN_IMPRESSIONS }
  end

  private

  # do melhor para o pior: mais conversas primeiro; empate decide pelo aproveitamento
  def ranked
    @rows.map { |row| enrich(row) }
         .sort_by { |row| [-row[:conversations], -row[:yield_1000].to_f, -row[:impressions]] }
         .first(MAX_ROWS)
  end

  def enrich(row)
    impressions = row[:impressions].to_i
    clicks = row[:link_clicks].to_i
    conversations = row[:conversations].to_i
    { key: row[:key].to_s, label: row[:label].to_s, impressions: impressions, link_clicks: clicks, conversations: conversations,
      clicks_per_100: per(clicks, impressions, 100), conversations_per_100: per(conversations, clicks, 100),
      yield_1000: per(conversations, impressions, 1000), spend: row[:spend], cost_conversation: row[:cost_conversation] }
  end

  def per(part, whole, scale)
    whole.positive? ? (part.to_f / whole * scale).round(2) : nil
  end

  def eligible(list)
    list.select { |row| row[:impressions] >= MIN_IMPRESSIONS && row[:yield_1000] }
  end

  # a linha da ponta (maior ou menor) — só quando ela está sozinha na ponta
  def unique_edge(list, field, side, noise: false)
    return nil if list.size < 2

    sorted = list.sort_by { |row| row[field].to_f }
    sorted.reverse! if side == :max
    first, second = sorted.first(2)
    top = [first[field].to_f, second[field].to_f].max
    return nil if top.zero?

    gap = (first[field].to_f - second[field].to_f).abs / top
    gap > margin(first, second, noise) ? first[:key] : nil
  end

  def margin(first, second, noise)
    return TIE unless noise

    smallest = [first[:conversations], second[:conversations]].min
    smallest.positive? ? [TIE, 1 / Math.sqrt(smallest)].max : 1.0
  end

  def badges_for(row, picks)
    picks.filter_map { |name, key| BADGES[name].merge(key: name.to_s) if key == row[:key] }
  end

  # ── frase-resumo ──────────────────────────────────────────────────────────
  def summary(list, picks)
    return nil if list.empty?
    return "Só há uma linha aqui (#{list.first[:label]}): não dá para comparar." if list.size == 1

    find = ->(key) { list.find { |row| row[:key] == key } }
    parts = [volume_sentence(find.call(picks[:most]), find.call(picks[:least]), list),
             yield_sentence(find.call(picks[:best]), find.call(picks[:worst]))].compact
    parts.join(' ')
  end

  def volume_sentence(most, least, list)
    word = PLACES[@kind].first
    return "O anúncio rende mais #{word} #{most[:label]} (#{count(most)}) e menos #{word} #{least[:label]} (#{count(least)})." if most && least
    return "O anúncio rende mais #{word} #{most[:label]} (#{count(most)}); atrás, há empate." if most
    return "Na frente há empate; o anúncio rende menos #{word} #{least[:label]} (#{count(least)})." if least

    tie_sentence(list)
  end

  def tie_sentence(list)
    values = list.pluck(:conversations)
    return "Não há diferença relevante entre #{PLACES[@kind].last}: os números são praticamente iguais." if values.uniq.size == 1

    front = values.count(values.max)
    back = values.count(values.min)
    "Não há um destaque único: #{front} linhas empatam na frente (#{thousands(values.max)} conversas cada) " \
      "e #{back} atrás (#{thousands(values.min)} cada)."
  end

  def yield_sentence(best, worst)
    return 'No aproveitamento (conversas a cada 1.000 exibições) não há diferença relevante.' if best.nil? && worst.nil?

    parts = []
    parts << "o melhor é #{best[:label]} (#{number(best[:yield_1000])} conversas a cada 1.000 exibições)" if best
    parts << "o pior é #{worst[:label]} (#{number(worst[:yield_1000])})" if worst
    "No aproveitamento, #{parts.join(' e ')}."
  end

  def count(row)
    "#{thousands(row[:conversations])} #{row[:conversations] == 1 ? 'conversa' : 'conversas'}"
  end

  def thousands(value)
    value.to_i.to_s.reverse.scan(/\d{1,3}/).join('.').reverse
  end

  def number(value)
    (value.to_f % 1).zero? ? value.to_i.to_s : value.to_f.round(1).to_s.tr('.', ',')
  end
end
