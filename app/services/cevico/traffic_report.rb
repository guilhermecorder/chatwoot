# 📈 RESULTADOS DE TRÁFEGO das Páginas — os números de um período (item 329,
# 05/10: "coloque as taxas de conversão ao longo das etapas do funil… gráficos
# em linha… precisamos poder otimizar a página").
#
# O caminho de cada visita, na ordem: VISITA → CLIQUE no WhatsApp → LEAD na
# caixa (chegou com o Protocolo da página) → AGENDOU consulta → CIRURGIA.
#   visitas e cliques   cevico_page_traffic (página × dia × origem × campanha)
#   leads               contatos carimbados com page_ads (Protocolo), pela data
#                       em que chegaram na caixa
#   agendou             esse lead tem consulta na Agenda
#   cirurgia e receita  o card dele chegou numa etapa de cirurgia (mesma régua
#                       do relatório de Anúncios)
# Agendou e cirurgia são dos LEADS DO PERÍODO (turma): o lead de hoje pode
# agendar semana que vem e o número sobe sozinho.
#
# Além dos totais por página / origem / campanha (o que a tela já mostrava),
# entrega a SÉRIE por dia, semana ou mês (para os gráficos em linha), o quanto
# da página foi lido e os campos de SEO de cada página (para os diagnósticos).
class Cevico::TrafficReport # rubocop:disable Metrics/ClassLength
  METRICS = %i[views cta leads booked conversions].freeze
  SCROLL_MARKS = %w[25 50 75 100].freeze
  MONTHS = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze

  attr_reader :since_date, :until_date

  def initialize(account, since_date, until_date)
    @account = account
    @since_date = since_date
    @until_date = until_date
  end

  def totals
    @totals ||= rows.each_with_object(blank_bucket) do |row, sum|
      sum.each_key { |key| sum[key] += row[key] }
    end
  end

  # honestidade do rastreio: quantos Protocolos foram gerados no clique ×
  # quantos chegaram na caixa (paciente manteve o código na mensagem)
  def protocol
    refs = @account.cevico_page_refs.where(created_at: since_date.beginning_of_day..until_date.end_of_day)
    { minted: refs.count, matched: refs.where.not(contact_id: nil).count }
  end

  # ── por página (com origens e campanhas) ──────────────────────────────
  def rows
    @rows ||= begin
      by_page = Hash.new { |h, k| h[k] = blank_row }
      add_traffic(by_page)
      add_leads(by_page)
      by_page.filter_map { |page_id, row| page_row(page_id, row) }
             .sort_by { |r| [-r[:conversions], -r[:leads], -r[:views]] }
    end
  end

  # as páginas com movimento + as PUBLICADAS que ficaram sem visita nem lead
  # no período (linha zerada) — é a lista que os diagnósticos leem
  def rows_with_idle
    seen = rows.pluck(:page_id).to_set
    idle = pages_by_id.values.select { |page| page.status == 'published' && seen.exclude?(page.id) }
    rows + idle.map { |page| page_row(page.id, blank_row).merge(idle: true) }
  end

  # ── série do período (gráficos em linha) ──────────────────────────────
  # { granularity, labels, views: [..], cta: [..], leads: [..], booked: [..],
  #   conversions: [..], by_source: { origem => { views: [..], cta: [..], leads: [..] } } }
  def series # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    index = buckets.each_with_index.to_h { |(key, _label), i| [key, i] }
    out = METRICS.index_with { Array.new(buckets.size, 0) }
    by_source = Hash.new { |h, k| h[k] = { views: Array.new(buckets.size, 0), cta: Array.new(buckets.size, 0), leads: Array.new(buckets.size, 0) } }
    daily_traffic.each do |date, _page_id, source, views, cta|
      i = index[bucket_key(date)]
      add_point(out, by_source[source], i, views: views, cta: cta)
    end
    attributed_leads.each do |contact_id, _page_id, source, _campaign, captured_at|
      i = index[bucket_key(captured_at.in_time_zone.to_date)]
      add_point(out, by_source[source.presence || 'direto'], i, leads: 1, booked: booked?(contact_id) ? 1 : 0,
                                                                conversions: converted_values.key?(contact_id) ? 1 : 0)
    end
    out.merge(granularity: granularity, labels: buckets.map(&:last), by_source: by_source)
  end

  def granularity
    days = (until_date - since_date).to_i + 1
    return :day if days <= 45
    return :week if days <= 400

    :month
  end

  private

  def add_point(out, source_bucket, index, values)
    return if index.nil?

    values.each do |key, n|
      out[key][index] += n
      source_bucket[key][index] += n if source_bucket.key?(key)
    end
  end

  def buckets
    @buckets ||= case granularity
                 when :week then step_buckets(since_date.beginning_of_week, 7) { |d| d.strftime('%d/%m') }
                 when :month then month_buckets
                 else (since_date..until_date).map { |d| [d.iso8601, d.strftime('%d/%m')] }
                 end
  end

  def step_buckets(start, step)
    list = []
    day = start
    while day <= until_date
      list << [day.iso8601, yield(day)]
      day += step
    end
    list
  end

  def month_buckets
    list = []
    day = since_date.beginning_of_month
    while day <= until_date
      list << [day.iso8601, "#{MONTHS[day.month - 1]}/#{day.strftime('%y')}"]
      day = day.next_month
    end
    list
  end

  def bucket_key(date)
    case granularity
    when :week then date.beginning_of_week.iso8601
    when :month then date.beginning_of_month.iso8601
    else date.iso8601
    end
  end

  # ── tráfego (visitas e cliques) ───────────────────────────────────────
  # [data, página, origem, visitas, cliques]
  def daily_traffic
    @daily_traffic ||= @account.cevico_page_traffic.where(date: since_date..until_date)
                               .group(:date, :cevico_page_id, :source)
                               .pluck(:date, :cevico_page_id, :source, Arel.sql('SUM(views)'), Arel.sql('SUM(cta_clicks)'))
  end

  def campaign_traffic
    @account.cevico_page_traffic.where(date: since_date..until_date).where.not(campaign: '')
            .group(:cevico_page_id, :campaign)
            .pluck(:cevico_page_id, :campaign, Arel.sql('SUM(views)'), Arel.sql('SUM(cta_clicks)'))
  end

  def add_traffic(by_page) # rubocop:disable Metrics/AbcSize
    daily_traffic.each do |date, page_id, source, views, cta|
      row = by_page[page_id]
      [row, row[:sources][source] ||= blank_bucket].each do |bucket|
        bucket[:views] += views
        bucket[:cta] += cta
      end
      spark = (row[:spark][bucket_key(date)] ||= [0, 0])
      spark[0] += views
      spark[1] += cta
    end
    campaign_traffic.each do |page_id, campaign, views, cta|
      bucket = (by_page[page_id][:campaigns][campaign] ||= blank_bucket)
      bucket[:views] += views
      bucket[:cta] += cta
    end
  end

  # ── leads carimbados (Protocolo → page_ads) e a jornada deles ─────────
  # [contato, página, origem, campanha, quando chegou] — página nula = lead do HUB
  def attributed_leads
    @attributed_leads ||= @account.contacts
                                  .where("additional_attributes -> 'page_ads' IS NOT NULL")
                                  .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz >= ?", since_date.beginning_of_day)
                                  .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz <= ?", until_date.end_of_day)
                                  .pluck(:id,
                                         Arel.sql("(additional_attributes -> 'page_ads' ->> 'page_id')::bigint"),
                                         Arel.sql("additional_attributes -> 'page_ads' ->> 'source'"),
                                         Arel.sql("additional_attributes -> 'page_ads' ->> 'campaign'"),
                                         Arel.sql("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz"))
  end

  def add_leads(by_page)
    attributed_leads.each do |contact_id, page_id, source, campaign, _captured_at|
      row = by_page[page_id]
      buckets = [row, row[:sources][source.presence || 'direto'] ||= blank_bucket]
      buckets << (row[:campaigns][campaign] ||= blank_bucket) if campaign.present?
      buckets.each { |bucket| add_lead(bucket, contact_id) }
    end
  end

  def add_lead(bucket, contact_id)
    bucket[:leads] += 1
    bucket[:booked] += 1 if booked?(contact_id)
    return unless converted_values.key?(contact_id)

    bucket[:conversions] += 1
    bucket[:revenue] += converted_values[contact_id].to_f
  end

  def booked?(contact_id)
    booked_contact_ids.include?(contact_id)
  end

  # contatos que AGENDARAM consulta (consulta da Agenda ligada ao contato)
  def booked_contact_ids
    @booked_contact_ids ||= begin
      ids = attributed_leads.map(&:first)
      ids.empty? ? Set.new : @account.tasks.where(task_type: 'consulta', contact_id: ids).distinct.pluck(:contact_id).to_set
    end
  end

  # mesma régua do relatório de Anúncios: etapas com "cirurgia" no nome
  # (sem as de indicação), ou as escolhidas na config do Meta Ads
  def conversion_stage_ids
    @conversion_stage_ids ||= begin
      configured = Array(meta_config['conversion_stage_ids']).map(&:to_i).reject(&:zero?)
      if configured.any?
        configured
      else
        base = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id })
                         .where('crm_stages.name ILIKE ?', '%cirurgia%')
        strict = base.where.not('crm_stages.name ILIKE ?', '%indica%').pluck(:id)
        strict.any? ? strict : base.pluck(:id)
      end
    end
  end

  # contato → valor do card, só de quem chegou na etapa de conversão
  def converted_values
    @converted_values ||= begin
      contact_ids = attributed_leads.map(&:first)
      if contact_ids.empty? || conversion_stage_ids.empty?
        {}
      else
        cards = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }).where(contact_id: contact_ids)
        converted_ids = cards.where(stage_id: conversion_stage_ids).pluck(:id) |
                        Crm::StageLog.where(crm_contact_id: cards.select(:id), stage_id: conversion_stage_ids).pluck(:crm_contact_id)
        cards.where(id: converted_ids).pluck(:contact_id, :value).to_h
      end
    end
  end

  def meta_config
    @meta_config ||= CrmSetting.find_by(account: @account)&.meta_ads_config || {}
  end

  # ── a linha de cada página ────────────────────────────────────────────
  def pages_by_id
    @pages_by_id ||= @account.cevico_pages
                             .select(:id, :title, :slug, :emoji, :status, :category, :meta_title, :meta_description,
                                     :seo_keywords, :daily_stats, :ab_variants, :created_at)
                             .index_by(&:id)
  end

  def page_row(page_id, row) # rubocop:disable Metrics/AbcSize
    base = row.merge(revenue: row[:revenue].round(2), spark: spark_points(row[:spark]))
    # leads do HUB (porta de entrada, sem página) ganham linha própria
    if page_id.nil?
      return base.merge(page_id: nil, title: 'Porta de entrada (hub)', slug: '', emoji: '🚪', status: 'published',
                        category: 'captacao', scroll: {}, seo: nil)
    end

    page = pages_by_id[page_id]
    return nil if page.nil?

    base.merge(page_id: page.id, title: page.title, slug: page.slug, emoji: page.emoji, status: page.status,
               category: page.category, scroll: scroll_of(page), seo: seo_of(page), ab_running: page.ab_test_running?,
               public_url: Cevico::PublicSite.page_url(page.slug), age_days: (Date.current - page.created_at.to_date).to_i)
  end

  def spark_points(spark)
    buckets.map { |key, _label| spark[key] || [0, 0] }
  end

  # até onde leram (25/50/75/100% da página), somado nos dias do período
  def scroll_of(page) # rubocop:disable Metrics/CyclomaticComplexity
    totals = SCROLL_MARKS.index_with { 0 }
    (page.daily_stats || {}).each do |day, stats|
      next unless day.between?(since_date.iso8601, until_date.iso8601)

      (stats['scroll'] || {}).each { |mark, n| totals[mark] += n.to_i if totals.key?(mark) }
    end
    totals.values.sum.zero? ? {} : totals
  end

  def seo_of(page)
    { title: page.meta_title.to_s.strip, description: page.meta_description.to_s.strip,
      keywords: page.seo_keywords.to_s.split(',').map(&:strip).compact_blank }
  end

  def blank_bucket
    { views: 0, cta: 0, leads: 0, booked: 0, conversions: 0, revenue: 0.0 }
  end

  def blank_row
    blank_bucket.merge(sources: {}, campaigns: {}, spark: {})
  end
end
