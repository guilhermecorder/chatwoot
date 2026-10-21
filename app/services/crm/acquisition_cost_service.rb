# 💰 FINANCEIRO & CAC (item 318, 03/10/2026 — "preciso descobrir o CAC afinal").
# Decisões dele:
#   • cliente conquistado = paciente com a 1ª CIRURGIA REALIZADA no período
#     (Crm::AcquisitionPatients);
#   • DOIS CACs: o de ANÚNCIOS (Google + Meta ÷ pacientes que vieram dos
#     anúncios — é o que abre por canal e por campanha) e o TOTAL "tecnologia
#     e anúncios" (anúncios + WhatsApp + IA ÷ todos os pacientes novos);
#   • IA é gravada em US$: converte pela cotação do dia (PTAX) ou pela taxa
#     manual (projeção) — Crm::UsdRateService;
#   • Oftalmofácil (parceiros) em bloco SEPARADO, fora do CAC.
# Gastos: Google = GA4 (custo automático), Meta = conta de anúncios (Marketing
# API; campanhas pelo espelho diário cevico_ad_insights), WhatsApp = fatura da
# Meta (crm_whatsapp_charges, item 303), IA = crm_ai_usages.
class Crm::AcquisitionCostService # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  PEOPLE_LIMIT = 400

  def initialize(account:, since:, until_at:, manual_usd: nil)
    @account = account
    @from = since.in_time_zone(TZ).to_date
    @to = until_at.in_time_zone(TZ).to_date
    @since = since
    @until_at = until_at
    @manual_usd = manual_usd.to_f.positive? ? manual_usd.to_f.round(4) : nil
  end

  def call
    {
      period: { from: @from.iso8601, to: @to.iso8601, days: (@to - @from).to_i + 1 },
      usd: usd_info,
      spend: spend,
      summary: summary,
      channels: channels,
      campaigns: campaigns,
      monthly: monthly,
      partner: partner_block,
      people: people,
      sources: patient_sources,
      bulk_skipped: patients.bulk_skipped
    }
  end

  # gasto do período sem a conta dos pacientes (o Financeiro usa no "Marketing")
  def ads_spend
    spend[:ads]
  end

  private

  # ══ GASTOS ══
  def spend
    @spend ||= begin
      ads = google[:cost].to_f + meta[:spend].to_f
      tech = whatsapp[:brl].to_f + ai[:brl].to_f
      { google: google, meta: meta, whatsapp: whatsapp.except(:daily_brl), ai: ai,
        ads: ads.round(2), tech: tech.round(2), total: (ads + tech).round(2) }
    end
  end

  def google
    @google ||= begin
      data = Rails.cache.fetch(['cevico_google_cost', @account.id, @from.iso8601, @to.iso8601], expires_in: 10.minutes) do
        Crm::GoogleAdCostService.new(account: @account, since_date: @from, until_date: @to).call
      end
      { configured: data[:configured], cost: data[:cost].to_f, error: data[:error] }
    end
  end

  def meta # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @meta ||= begin
      data = Rails.cache.fetch(['cevico_meta_spend', @account.id, @from.iso8601, @to.iso8601], expires_in: 10.minutes) do
        Crm::MetaInsightsService.new(account: @account, since_date: @from, until_date: @to).call
      end
      live = data[:configured] && data[:error].blank?
      # sem resposta ao vivo: o espelho diário dos anúncios (sincronizado à noite)
      mirror = live ? nil : meta_campaign_spend.values.sum.round(2)
      { configured: data[:configured], spend: live ? data[:spend].to_f : mirror.to_f, error: data[:error],
        source: if live
                  'meta'
                else
                  (mirror.to_f.positive? ? 'espelho' : nil)
                end }
    end
  end

  def whatsapp
    @whatsapp ||= begin
      scope = Crm::WhatsappCharge.where(account_id: @account.id)
      currency = scope.order(day: :desc).pick(:currency).presence || 'BRL'
      daily = scope.where(day: @from..@to).group(:day).sum(:cost)
      daily_brl = daily.to_h { |day, cost| [day, currency == 'USD' ? cost.to_f * usd_on(day) : cost.to_f] }
      { synced: scope.exists?, currency: currency, cost: daily.values.sum(&:to_f).round(2),
        brl: daily_brl.values.sum.round(2), daily_brl: daily_brl }
    end
  end

  def ai
    @ai ||= begin
      daily = ai_daily_usd
      usd = daily.values.sum
      brl = daily.sum { |day, cost| cost * usd_on(day) }
      { usd: usd.round(2), brl: brl.round(2), calls: Crm::AiUsage.where(account_id: @account.id, created_at: @since..@until_at).count }
    end
  end

  def ai_daily_usd
    @ai_daily_usd ||= Crm::AiUsage.where(account_id: @account.id, created_at: @since..@until_at)
                                  .group(Arel.sql("DATE(crm_ai_usages.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')"))
                                  .sum(:cost_usd).transform_keys(&:to_date).transform_values(&:to_f)
  end

  # ══ DÓLAR ══
  def daily_rates
    @daily_rates ||= Crm::UsdRateService.rates_for(@from, @to)
  end

  def usd_on(day)
    return @manual_usd if @manual_usd

    daily_rates[day.to_date] || daily_rates.values.last || Crm::UsdRateService.last_known&.dig(:rate).to_f
  end

  def usd_info
    rates = daily_rates.values.compact
    last = Crm::UsdRateService.last_known
    {
      mode: if @manual_usd
              'manual'
            else
              (rates.any? ? 'ptax' : 'missing')
            end,
      manual: @manual_usd,
      avg: rates.any? ? (rates.sum / rates.size).round(4) : nil,
      last_rate: last&.dig(:rate), last_date: last&.dig(:date)
    }
  end

  # ══ PACIENTES ══
  def patients
    @patients ||= Crm::AcquisitionPatients.new(@account, from: @from, to: @to)
  end

  def attribution
    @attribution ||= Crm::AcquisitionChannel.new(@account)
                                            .for_contacts((patients.cevico.map(&:contact_id) + revenue_contact_ids).compact)
  end

  def revenue_contact_ids
    patients.revenue_keys.select { |k| k.is_a?(Integer) }
  end

  def channel_of(key)
    attribution[key] || Crm::AcquisitionChannel::Result.new(
      channel: 'organico',
      detail: key.to_s.start_with?('of:') ? 'só no Oftalmofácil (sem cadastro no sistema)' : Crm::AcquisitionChannel::NO_TRACE
    )
  end

  # receita do período da CEVICO (sem parceiros), por canal e por campanha
  def revenue_by
    @revenue_by ||= patients.revenue_keys.reject { |k| patients.partner?(k) || partner_contact?(k) }
                            .each_with_object(Hash.new(0.0)) do |key, acc|
      ch = channel_of(key)
      value = patients.revenue_of(key)
      acc[ch.channel] += value
      acc[[ch.channel, ch.campaign]] += value if ch.campaign
      acc[:total] += value
    end
  end

  def partner_contact?(key)
    key.is_a?(Integer) && Crm::PartnerGuard.excluded_contact_ids(@account).include?(key)
  end

  # ══ LEADS (universo oficial) por canal e campanha — para o custo por lead ══
  def leads
    @leads ||= begin
      ids = Crm::LeadsUniverse.scope(@account, @since, @until_at).pluck(:id)
      classifier = Crm::AcquisitionChannel.new(@account)
      ids.each_slice(2000).with_object(Hash.new(0)) do |slice, acc|
        classifier.for_contacts(slice).each_value do |r|
          acc[r.channel] += 1
          acc[[r.channel, r.campaign]] += 1 if r.campaign
          acc[:total] += 1
        end
      end
    end
  end

  # ══ RESUMO ══
  def summary # rubocop:disable Metrics/AbcSize
    all = patients.cevico
    paid = all.count { |p| Crm::AcquisitionChannel::PAID.include?(channel_of(p.key).channel) }
    paid_revenue = Crm::AcquisitionChannel::PAID.sum { |c| revenue_by[c] }
    {
      patients: all.size,
      paid_patients: paid,
      leads: leads[:total],
      paid_leads: leads['google'] + leads['meta'],
      revenue: revenue_by[:total].round(2),
      paid_revenue: paid_revenue.round(2),
      cac_ads: per(spend[:ads], paid),
      cac_ads_blended: per(spend[:ads], all.size),
      cac_total: per(spend[:total], all.size),
      roas_ads: ratio(paid_revenue, spend[:ads]),
      roas_total: ratio(revenue_by[:total], spend[:total]),
      cpl_ads: per(spend[:ads], leads['google'] + leads['meta'])
    }
  end

  def channels # rubocop:disable Metrics/AbcSize
    Crm::AcquisitionChannel::CHANNELS.map do |key, label|
      count = patients.cevico.count { |p| channel_of(p.key).channel == key }
      cost = { 'google' => google[:cost], 'meta' => meta[:spend] }[key].to_f
      {
        key: key, label: label, spend: cost.round(2), patients: count, leads: leads[key],
        revenue: revenue_by[key].round(2), cac: key == 'organico' ? nil : per(cost, count),
        cpl: key == 'organico' ? nil : per(cost, leads[key]), roas: key == 'organico' ? nil : ratio(revenue_by[key], cost),
        details: channel_details(key)
      }
    end
  end

  # de onde vieram os orgânicos (e as portas de entrada dos pagos)
  def channel_details(key)
    patients.cevico.map { |p| channel_of(p.key) }.select { |r| r.channel == key }
            .group_by(&:detail).map { |detail, rows| { label: detail, patients: rows.size } }
            .sort_by { |r| -r[:patients] }
  end

  # ══ CAMPANHAS ══
  def campaigns # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows = Hash.new { |h, k| h[k] = { channel: k[0], name: k[1], spend: 0.0, patients: 0 } }
    meta_campaign_spend.each { |name, cost| rows[['meta', name]][:spend] += cost }
    google_campaign_spend.each { |name, cost| rows[['google', name]][:spend] += cost }
    patients.cevico.each do |p|
      ch = channel_of(p.key)
      rows[[ch.channel, ch.campaign]][:patients] += 1 if ch.campaign
    end
    rows.each_value do |r|
      k = [r[:channel], r[:name]]
      r[:leads] = leads[k]
      r[:revenue] = revenue_by[k].round(2)
      r[:spend] = r[:spend].round(2)
      r[:cac] = per(r[:spend], r[:patients])
      r[:roas] = ratio(r[:revenue], r[:spend])
    end
    rows.values.reject { |r| r[:spend].zero? && r[:patients].zero? && r[:leads].zero? && r[:revenue].zero? }
        .sort_by { |r| [-r[:spend], -r[:patients]] }
  end

  # campanha da Meta pelo espelho diário dos anúncios (ad_id → campanha)
  def meta_campaign_spend
    @meta_campaign_spend ||= meta_spend_by_campaign
  end

  def meta_spend_by_campaign
    by_ad = Crm::AdInsight.where(account_id: @account.id).between(@from, @to)
                          .group(:ad_id).sum(Arel.sql("COALESCE((metrics->>'spend')::numeric, 0)"))
    names = Crm::AdCreative.where(account_id: @account.id, ad_id: by_ad.keys).pluck(:ad_id, :campaign_name, :campaign_id)
                           .to_h { |ad, name, cid| [ad, name.presence || cid] }
    by_ad.each_with_object(Hash.new(0.0)) do |(ad, cost), acc|
      acc[names[ad].presence || Crm::AcquisitionChannel::NO_CAMPAIGN] += cost.to_f
    end
  end

  def google_campaign_spend
    data = Rails.cache.fetch("cevico:google_keywords:#{@account.id}:#{@from}:#{@to}", expires_in: 10.minutes) do
      Crm::GoogleKeywordsService.new(account: @account, since_date: @from, until_date: @to).call
    end
    Array(data.dig(:campaigns, :rows)).each_with_object(Hash.new(0.0)) do |r, acc|
      name = r[:term] == '(not set)' ? Crm::AcquisitionChannel::NO_CAMPAIGN : r[:term]
      acc[name] += r[:cost].to_f
    end
  rescue StandardError
    {}
  end

  # ══ MÊS A MÊS ══
  def monthly # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    months = month_keys
    return [] if months.size < 2

    g = cached_months('google', Crm::GoogleMonthlyCostService)
    m = meta[:source] == 'espelho' ? meta_mirror_months : cached_months('meta', Crm::MetaMonthlySpendService)
    wa = whatsapp[:daily_brl].group_by { |day, _| day.strftime('%Y-%m') }.transform_values { |rows| rows.sum(&:last) }
    ia = ai_daily_usd.group_by { |day, _| day.strftime('%Y-%m') }
                     .transform_values { |rows| rows.sum { |day, usd| usd * usd_on(day) } }
    by_month = patients.cevico.group_by { |p| p.first_on.strftime('%Y-%m') }
    months.map do |ym|
      list = by_month[ym] || []
      paid = list.count { |p| Crm::AcquisitionChannel::PAID.include?(channel_of(p.key).channel) }
      ads = g[ym].to_f + m[ym].to_f
      tech = wa[ym].to_f + ia[ym].to_f
      { month: ym, google: g[ym].to_f.round(2), meta: m[ym].to_f.round(2), whatsapp: wa[ym].to_f.round(2),
        ai: ia[ym].to_f.round(2), ads: ads.round(2), total: (ads + tech).round(2), patients: list.size, paid_patients: paid,
        cac_ads: per(ads, paid), cac_total: per(ads + tech, list.size) }
    end
  end

  def meta_mirror_months
    Crm::AdInsight.where(account_id: @account.id).between(@from, @to)
                  .group(Arel.sql("TO_CHAR(date, 'YYYY-MM')")).sum(Arel.sql("COALESCE((metrics->>'spend')::numeric, 0)"))
                  .transform_values(&:to_f)
  end

  def month_keys
    keys = []
    d = @from.beginning_of_month
    while d <= @to
      keys << d.strftime('%Y-%m')
      d = d.next_month
    end
    keys
  end

  def cached_months(kind, klass)
    data = Rails.cache.fetch(['cevico_monthly_spend', kind, @account.id, @from.iso8601, @to.iso8601], expires_in: 30.minutes) do
      klass.new(account: @account, since_date: @from, until_date: @to).call
    end
    data[:months] || {}
  end

  # ══ OFTALMOFÁCIL (parceiros) — fora do CAC ══
  def partner_block
    keys = patients.revenue_keys.select { |k| patients.partner?(k) || partner_contact?(k) }
    {
      patients: patients.partner.size,
      revenue: keys.sum { |k| patients.revenue_of(k) }.round(2),
      result: patients.partner_result.round(2)
    }
  end

  # ══ LISTA (cada número explicado: quem são os pacientes do CAC) ══
  def people # rubocop:disable Metrics/AbcSize
    list = patients.cevico.sort_by(&:first_on).reverse.first(PEOPLE_LIMIT)
    names = @account.contacts.where(id: list.filter_map(&:contact_id)).pluck(:id, :name).to_h
    list.map do |p|
      ch = channel_of(p.key)
      { key: p.key.to_s, contact_id: p.contact_id, name: names[p.contact_id].presence || p.name.presence || 'Paciente',
        date: p.first_on.iso8601, source: p.source, channel: ch.channel, detail: ch.detail, campaign: ch.campaign,
        revenue: patients.revenue_of(p.key).round(2) }
    end
  end

  # de onde veio a DATA da cirurgia (CRM × Agenda × Oftalmofácil)
  def patient_sources
    patients.cevico.group_by(&:source).transform_values(&:size)
  end

  def per(cost, count)
    count.to_i.positive? && cost.to_f.positive? ? (cost.to_f / count).round(2) : nil
  end

  def ratio(revenue, cost)
    cost.to_f.positive? ? (revenue.to_f / cost).round(2) : nil
  end
end
