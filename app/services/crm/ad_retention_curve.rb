# 📉 Curva de retenção DETALHADA de um anúncio em vídeo (item 287).
#
# De onde vem: a Meta devolve, por dia, `video_play_curve_actions` — 22 valores
# com a % das reproduções que ainda assistia em cada segundo (0 a 14 s, depois
# as faixas que começam em 15, 20, 25, 30, 40, 50 e 60 s). Aqui os dias do
# período viram UMA curva (média ponderada pelas reproduções de cada dia).
#
# O que sai:
#   points        → a curva (segundo, % que ainda assiste, quantas reproduções)
#   average       → a mesma curva para a média da conta (comparação)
#   marks         → os marcos 3 s · 25 % · 50 % · 75 % · fim, com a contagem real da Meta
#   biggest_drop  → o trecho onde mais gente foi embora (e a maior queda depois do gancho)
#   segments      → o que está sendo FALADO em cada trecho (quando a transcrição tem tempo)
#   clicks        → "cliques por quem chegou até aqui" — leitura APROXIMADA: a Meta
#                   não informa em que segundo cada clique aconteceu
#
# Sem a curva da Meta (dados antigos, carga anterior ao item 287), cai para os
# 6 marcos de sempre (% das impressões), no mesmo formato.
#
# Rodada 4: tudo fala em TEMPO e em ZONA. Os marcos viram segundos pela duração
# do vídeo ("25% · 8 s") e o vídeo é dividido em Gancho · Corpo · CTA
# (Crm::AdVideoZones); cada queda diz em que zona aconteceu e `drops_summary`
# resume onde está a maior perda.
class Crm::AdRetentionCurve # rubocop:disable Metrics/ClassLength
  SECONDS = ((0..14).to_a + [15, 20, 25, 30, 40, 50, 60]).freeze
  MARKS = [['p25', '25%', 0.25], ['p50', '50%', 0.5], ['p75', '75%', 0.75], ['p100', 'fim', 1.0]].freeze
  DURATION_UNKNOWN = 'Duração do vídeo ainda não conhecida (aparece depois da próxima carga da Meta ou da transcrição): ' \
                     'por isso os marcos aparecem em % do vídeo, sem os segundos.'.freeze
  CLICK_NOTE = 'A Meta não informa em que segundo cada clique aconteceu. Esta é uma leitura aproximada: ' \
               'os cliques no link do período divididos por quem chegou a cada ponto do vídeo.'.freeze

  # list = dias do anúncio; account_list = dias de todos os vídeos da conta (média)
  def initialize(creative:, list:, account_list: [])
    @creative = creative
    @list = list
    @account_list = account_list
    @totals = Crm::AdMetrics.sum(list)
  end

  def call # rubocop:disable Metrics/AbcSize
    return nil unless @totals['impressions'].to_f.positive? && @totals['plays_3s'].to_f.positive?

    data = curve_days.any? ? detailed : by_marks
    @zones = Crm::AdVideoZones.new(duration: data[:duration], transcript: @creative.transcript, points: data[:points])
    drops = top_drops(data[:points])
    data.merge(biggest_drop: drop_for(data[:points]), biggest_drop_after_hook: drop_for(data[:points], from: 3),
               top_drops: drops, drops_summary: @zones.summary(drops), zones: @zones.list, zones_estimated: @zones.estimated?,
               zones_note: @zones.note, duration_note: data[:duration] ? nil : DURATION_UNKNOWN,
               segments: segments_for(data), clicks: clicks, avg_watch: @totals['avg_watch'].to_f,
               period_days: @list.size)
  end

  private

  # ── curva segundo a segundo (Meta) ────────────────────────────────────────
  def curve_days
    @curve_days ||= @list.select { |m| m['play_curve'].is_a?(Array) && m['play_curve'].any? && m['plays'].to_f.positive? }
  end

  def detailed
    base = Crm::AdMetrics.sum(curve_days)
    curve = weighted_curve(curve_days)
    length = duration(curve, base)
    points = curve_points(curve, base['plays'], length[:seconds], end_pct: share(base['p100'], base['plays']))
    { source: 'meta_curve', axis: 'seconds', base: 'plays', base_label: 'das reproduções', base_total: base['plays'].to_i,
      curve_days: curve_days.size, duration: length[:seconds], duration_estimated: length[:estimated],
      points: points, average: average_points(points.last[:t]), marks: marks_for(base, base['plays'], length[:seconds]) }
  end

  def weighted_curve(days)
    weight = days.sum { |m| m['plays'].to_f }
    SECONDS.each_index.map do |i|
      (days.sum { |m| m['play_curve'][i].to_f * m['plays'].to_f } / weight / 100.0).clamp(0, 1).round(4)
    end
  end

  def curve_points(curve, plays, length, end_pct: nil)
    points = SECONDS.zip(curve).map { |t, pct| point(t, pct, plays) }
    return trim_zeros(points) unless length

    inside = points.select { |p| p[:t] < length }
    inside << point(length.round(1), end_pct || value_at(points, length), plays, label: 'fim')
  end

  # sem duração: corta a cauda de zeros (o vídeo acabou), deixando o primeiro zero
  def trim_zeros(points)
    last = points.rindex { |p| p[:pct].positive? } || 0
    points.first(last + 2)
  end

  def point(second, pct, base, label: nil)
    { t: second, label: label || "#{format_seconds(second)} s", pct: pct.to_f.clamp(0, 1).round(4), people: (pct.to_f * base.to_f).round }
  end

  def format_seconds(second)
    (second.to_f % 1).zero? ? second.to_i.to_s : second.to_f.round(1).to_s.tr('.', ',')
  end

  # média da conta: todos os dias de todos os vídeos com curva, até o mesmo segundo
  def average_points(max_second)
    days = @account_list.select { |m| m['play_curve'].is_a?(Array) && m['play_curve'].any? && m['plays'].to_f.positive? }
    return [] if days.empty?

    SECONDS.zip(weighted_curve(days)).select { |t, _| t <= max_second }.map { |t, pct| { t: t, pct: pct } }
  end

  # duração: a que a Meta informou (`length` do vídeo) → a da transcrição → uma
  # ESTIMATIVA pelo ponto em que a curva cruza o marco de 50 % (avisada na tela)
  def known_duration
    known = @creative.creative['video_length'].to_f
    known = @creative.transcript['duration'].to_f unless known.positive?
    known.positive? ? known.round(1) : nil
  end

  def duration(curve, base)
    return { seconds: known_duration, estimated: false } if known_duration

    half = crossing(SECONDS.zip(curve), share(base['p50'], base['plays']))
    { seconds: half ? (half * 2).round.clamp(3, 120) : nil, estimated: half.present? }
  end

  # em que segundo a curva desce até `target` (interpolando entre os pontos)
  def crossing(pairs, target)
    return nil if target.nil? || !target.positive?

    pairs.each_cons(2) do |(t1, v1), (t2, v2)|
      next unless v1 > v2 && target.between?(v2, v1)

      return t1 + ((t2 - t1) * (v1 - target) / (v1 - v2))
    end
    nil
  end

  # ── sem curva: os 6 marcos de sempre (% das impressões) ──────────────────
  def by_marks
    impressions = @totals['impressions'].to_f
    length = known_duration
    points = mark_points(impressions, length)
    { source: 'milestones', axis: length ? 'seconds' : 'marks', base: 'impressions', base_label: 'das impressões',
      base_total: impressions.to_i, curve_days: 0, duration: length, duration_estimated: false,
      points: points, average: [], marks: marks_for(@totals, impressions, length) }
  end

  # impressões → 3 s → 25 % → 50 % → 75 % → fim (em segundos quando se sabe a duração)
  def mark_points(impressions, length) # rubocop:disable Metrics/CyclomaticComplexity
    rows = [['Impressões', 1.0, 0], ['3 s', share(@totals['plays_3s'], impressions), 3]]
    rows += MARKS.map { |key, label, pos| [label, share(@totals[key], impressions), length && (length * pos).round(1)] }
    points = rows.map do |label, pct, second|
      point(0, pct, impressions, label: label).merge(t: length && second, axis_label: axis_label(label, length && second))
    end
    length ? points.sort_by { |p| p[:t] } : points
  end

  # no eixo: o marco e o segundo juntos ("25% · 8 s")
  def axis_label(label, second)
    return label if second.nil? || label.end_with?(' s')
    return '0 s' if label == 'Impressões'

    "#{label} · #{format_seconds(second)} s"
  end

  # ── marcos (contagem real da Meta em cada um) ────────────────────────────
  def marks_for(base, denominator, length)
    list = [mark('3s', '3 s', 3, base['plays_3s'], denominator)]
    MARKS.each do |key, label, pos|
      list << mark(key, label, length ? (length * pos).round(1) : nil, base[key], denominator)
    end
    list
  end

  def mark(key, label, second, count, denominator)
    { key: key, label: label, t: second, axis_label: axis_label(label, second), people: count.to_i, pct: share(count, denominator) }
  end

  def share(count, total)
    total.to_f.positive? ? (count.to_f / total).clamp(0, 1).round(4) : nil
  end

  # ── maior queda ───────────────────────────────────────────────────────────
  # no eixo em segundos, a queda é medida POR SEGUNDO (as faixas depois de 15 s
  # são mais largas); `from` ignora o começo (queda depois do gancho)
  def drop_for(points, from: nil)
    pairs = points.each_cons(2).select { |a, _| from.nil? || (a[:t] && a[:t] >= from) }
    worst = pairs.max_by { |a, b| drop_rate(a, b) }
    return nil if worst.nil? || (worst[0][:pct] - worst[1][:pct]) <= 0

    drop_row(*worst)
  end

  def drop_row(from, to)
    { from_t: from[:t], to_t: to[:t], from_label: from[:label], to_label: to[:label], from_pct: from[:pct], to_pct: to[:pct],
      drop: (from[:pct] - to[:pct]).round(4), people_lost: [from[:people] - to[:people], 0].max,
      speech: speech_between(from[:t], to[:t]), after_hook: from[:t].present? && from[:t] >= 3 }
      .merge(@zones ? @zones.for_drop(from, to) : {})
  end

  # as 3 a 5 MAIORES QUEDAS, da maior para a menor (rodada 2): trechos distintos
  # (vizinho de um trecho já escolhido fica de fora) e só quedas que contam
  # (pelo menos MIN_DROP de ponto percentual). Menos de 3 relevantes → mostra as que houver.
  MAX_DROPS = 5
  MIN_DROP = 0.01

  def top_drops(points) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    pairs = points.each_cons(2).to_a
    order = pairs.each_index.select { |i| (pairs[i][0][:pct] - pairs[i][1][:pct]) >= MIN_DROP }
                 .sort_by { |i| -drop_rate(*pairs[i]) }
    picked = []
    order.each do |i|
      break if picked.size >= MAX_DROPS

      picked << i unless picked.any? { |j| (j - i).abs <= 1 }
    end
    picked.each_with_index.map { |i, rank| drop_row(*pairs[i]).merge(rank: rank + 1) }
  end

  def drop_rate(from, to)
    drop = from[:pct] - to[:pct]
    span = from[:t] && to[:t] ? [to[:t] - from[:t], 1].max : 1
    drop / span.to_f
  end

  # ── o que está sendo falado em cada trecho ───────────────────────────────
  def transcript_segments
    @transcript_segments ||= Array(@creative.transcript['segments']).filter_map do |s|
      next unless s.is_a?(Hash) && s['text'].present?

      { start: s['start'].to_f, end: [s['end'].to_f, s['start'].to_f].max, text: s['text'].to_s }
    end
  end

  def segments_for(data)
    return [] unless data[:axis] == 'seconds'

    transcript_segments.map do |s|
      from = value_at(data[:points], s[:start])
      to = value_at(data[:points], s[:end])
      s.merge(pct_start: from, pct_end: to, people_lost: ([from - to, 0].max * data[:base_total]).round)
    end
  end

  def speech_between(from, to)
    return nil if from.nil? || to.nil?

    transcript_segments.select { |s| s[:start] < to && s[:end] > from }.pluck(:text).join(' ').presence
  end

  def value_at(points, second)
    timed = points.select { |p| p[:t] }
    return 0.0 if timed.empty?

    second = second.to_f.clamp(timed.first[:t], timed.last[:t])
    from, to = timed.each_cons(2).find { |x, y| second.between?(x[:t], y[:t]) } || [timed.last, timed.last]
    between(from, to, second)
  end

  def between(from, to, second)
    span = to[:t] - from[:t]
    return from[:pct] if span.zero?

    (from[:pct] + ((to[:pct] - from[:pct]) * (second - from[:t]) / span)).round(4)
  end

  # ── cliques por quem chegou até aqui (período inteiro) ───────────────────
  # `rate` = cliques ÷ quem chegou ao marco. `before_min` é uma conta certa:
  # se houve MAIS cliques do que pessoas que chegaram ao marco, pelo menos a
  # diferença clicou antes dele.
  # Rodada 4: cada linha vira % DE CONVERSÃO escrita ("0,7% de quem viu o anúncio clicou").
  CLICK_ROWS = [['impressions', 'Viu o anúncio', 'impressions', 'de quem viu o anúncio'],
                ['3s', 'Passou dos 3 s', 'plays_3s', 'de quem passou dos 3 s'],
                ['p25', 'Chegou a 25%', 'p25', 'de quem chegou a 25% do vídeo'], ['p50', 'Chegou a 50%', 'p50', 'de quem chegou à metade'],
                ['p75', 'Chegou a 75%', 'p75', 'de quem chegou a 75% do vídeo'],
                ['p100', 'Viu até o fim', 'p100', 'de quem viu até o fim']].freeze

  def clicks
    total = @totals['link_clicks'].to_i
    { link_clicks: total, note: CLICK_NOTE, source: 'Meta: cliques no link (inline_link_clicks) e contagem de quem chegou a cada marco do vídeo',
      marks: CLICK_ROWS.map { |key, label, field, who| click_row(key, label, who, @totals[field].to_i, total) } }
  end

  def click_row(key, label, who, reached, total)
    rate = reached.positive? ? (total / reached.to_f).round(4) : nil
    { key: key, label: label, who: who, reached: reached, rate: rate, rate_text: rate && percent(rate),
      conversion_text: rate ? "#{percent(rate)} #{who} clicou" : 'sem dado', before_min: [total - reached, 0].max }
  end

  def percent(rate)
    "#{format('%.1f', rate * 100).tr('.', ',')}%"
  end
end
