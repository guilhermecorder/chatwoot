# 🏆 RECORDES E CAMPEÕES do nosso próprio histórico (item 172, rodada 3):
# a filosofia é "nos superar um pouco, dia a dia, semana a semana, mês a mês".
# Lê tudo o que está em cevico_ad_insights e devolve, por métrica, o melhor
# dia, a melhor semana (calendário) e o melhor mês, a mediana das semanas,
# o momento atual (hoje/semana/mês) contra o anterior, e os campeões de
# gancho / corpo / CTA / custo por mês e de todos os tempos.
class Crm::CreativeRecords
  METRICS = %w[hook_rate hold_rate link_ctr conv_rate cost_conversation].freeze
  LOWER_IS_BETTER = %w[cost_conversation cost_surgery].freeze
  MIN_DAY = 300
  MIN_WEEK = 1500
  MIN_MONTH = 3000
  MIN_AD = 500
  PARTS = { hook: 'hook_rate', hold: 'hold_rate', cta: 'link_ctr', conv: 'conv_rate', cost: 'cost_conversation',
            # v2 (item 177): campeões de dinheiro — vêm da jornada do CRM (Crm::AdFunnel), não da Meta
            roas: 'roas', cac: 'cost_surgery', booking: 'booking_rate' }.freeze
  FUNNEL_PARTS = { roas: [:surgeries, 1], cac: [:surgeries, 1], booking: [:leads, 5] }.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  MONTHS_PT = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze

  def initialize(account:)
    @account = account
  end

  def call
    stamp = Crm::AdInsight.where(account_id: @account.id).maximum(:updated_at).to_i
    Rails.cache.fetch("crm:creative_records:#{@account.id}:#{stamp}", expires_in: 1.hour) { compute }
  end

  private

  def rows
    @rows ||= Crm::AdInsight.where(account_id: @account.id).order(:date).pluck(:ad_id, :date, :metrics)
  end

  def compute
    return { records: {}, months: [], all_time: {}, since: nil, until: nil } if rows.empty?

    {
      records: METRICS.index_with { |m| record_for(m) },
      months: months_champions,
      all_time: champions_for(rows),
      since: rows.first[1], until: rows.last[1]
    }
  end

  # ── séries agregadas da conta ──────────────────────────────────────────
  def by_day
    @by_day ||= rows.group_by { |_id, date, _m| date }.sort.to_h.transform_values { |list| Crm::AdMetrics.sum(list.map(&:last)) }
  end

  def by_week
    @by_week ||= rows.group_by { |_id, date, _m| date.beginning_of_week }.sort.to_h
                     .transform_values { |list| Crm::AdMetrics.sum(list.map(&:last)).merge('days' => list.map { |r| r[1] }.uniq.size) }
  end

  def by_month
    @by_month ||= rows.group_by { |_id, date, _m| date.beginning_of_month }.sort.to_h
                      .transform_values { |list| Crm::AdMetrics.sum(list.map(&:last)).merge('days' => list.map { |r| r[1] }.uniq.size) }
  end

  def rate(total, metric)
    Crm::AdMetrics.rates(total, video: total['plays_3s'].to_f.positive?)[metric]
  end

  def better?(metric, candidate, current)
    return true if current.nil?

    LOWER_IS_BETTER.include?(metric) ? candidate < current : candidate > current
  end

  def best_of(series, metric, min_impressions, min_days: 1) # rubocop:disable Metrics/CyclomaticComplexity
    best = nil
    series.each do |key, total|
      next if total['impressions'].to_f < min_impressions || (total['days'].to_i < min_days && total.key?('days'))

      value = rate(total, metric)
      next if value.nil?

      best = { value: value.round(4), at: key.iso8601 } if better?(metric, value, best&.dig(:value))
    end
    best
  end

  def median_of(series, metric, min_impressions)
    values = series.values.filter_map do |total|
      next if total['impressions'].to_f < min_impressions

      rate(total, metric)
    end.sort
    return nil if values.empty?

    mid = values.size / 2
    (values.size.odd? ? values[mid] : (values[mid - 1] + values[mid]) / 2.0).round(4)
  end

  # rubocop:disable Metrics/AbcSize
  def record_for(metric)
    today = TZ.today
    {
      lower_is_better: LOWER_IS_BETTER.include?(metric),
      best_day: best_of(by_day, metric, MIN_DAY),
      best_week: best_of(by_week, metric, MIN_WEEK, min_days: 4),
      best_month: best_of(by_month, metric, MIN_MONTH, min_days: 7),
      median_week: median_of(by_week, metric, MIN_WEEK) || median_of(by_day, metric, MIN_DAY),
      current: {
        day: value_at(by_day, today, metric), week: value_at(by_week, today.beginning_of_week, metric),
        month: value_at(by_month, today.beginning_of_month, metric)
      },
      previous: {
        day: value_at(by_day, today - 1, metric), week: value_at(by_week, (today - 7).beginning_of_week, metric),
        month: value_at(by_month, (today.beginning_of_month - 1).beginning_of_month, metric)
      }
    }
  end
  # rubocop:enable Metrics/AbcSize

  def value_at(series, key, metric)
    total = series[key]
    return nil if total.nil? || total['impressions'].to_f.zero?

    rate(total, metric)&.round(4)
  end

  # ── campeões (gancho / corpo / CTA / conversa / custo) ─────────────────
  def creatives
    @creatives ||= Crm::AdCreative.where(account_id: @account.id).with_attached_thumbnail.index_by(&:ad_id)
  end

  def months_champions
    rows.group_by { |_id, date, _m| date.beginning_of_month }.sort.map do |month, list|
      base = { month: month.iso8601, label: "#{MONTHS_PT[month.month - 1]}/#{month.year}", days: list.map { |r| r[1] }.uniq.size }
      base.merge(champions_for(list))
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def champions_for(list)
    per_ad = list.group_by(&:first).transform_values { |l| Crm::AdMetrics.sum(l.map(&:last)) }
    funnels = funnels_for(list)
    PARTS.to_h do |part, metric|
      best = nil
      per_ad.each do |ad_id, total|
        next if total['impressions'].to_f < MIN_AD
        next if part == :cost && total['conversations'].to_f < 5
        next if FUNNEL_PARTS[part] && funnels.dig(ad_id, FUNNEL_PARTS[part][0]).to_i < FUNNEL_PARTS[part][1]

        rates = rates_for(total, funnels[ad_id])
        value = rates[metric]
        next if value.nil?

        next unless better?(metric, value, best&.dig(:value))

        best = { ad_id: ad_id, value: value.round(4), conversations: total['conversations'].to_i, spend: total['spend'],
                 funnel: funnels[ad_id] || Crm::AdFunnel::EMPTY, rates: rates } # a teia do campeão
      end
      [part, best&.merge(describe(best[:ad_id], part))]
    end
  end

  # taxas da Meta + da jornada do CRM, no mesmo hash (chaves em texto)
  def rates_for(total, funnel)
    Crm::AdMetrics.rates(total, video: total['plays_3s'].to_f.positive?)
                  .merge(Crm::AdFunnel.rates(funnel, total['spend']).stringify_keys)
  end

  # jornada por anúncio no intervalo de datas da lista (cache por intervalo)
  def funnels_for(list)
    range = list.pluck(1).minmax
    @funnel_cache ||= {}
    @funnel_cache[range] ||= Crm::AdFunnel.by_ad(@account, range[0], range[1])
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def describe(ad_id, part)
    c = creatives[ad_id]
    return { ad_name: "Anúncio #{ad_id}", text: nil } unless c

    text = case part
           when :hold then c.body
           when :cta then Crm::AdCreativeParser.cta_label(c.cta)
           else c.hook
           end
    { ad_name: c.ad_name, text: text, thumbnail_url: c.thumbnail_src, format: c.format,
      hook: c.hook, body: c.body, cta_label: Crm::AdCreativeParser.cta_label(c.cta) }
  end
end
