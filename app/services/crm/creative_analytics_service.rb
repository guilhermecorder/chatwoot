# Monta a leitura da Central de Criativos (item 172) a partir do que está no
# banco (cevico_ad_creatives + cevico_ad_insights) cruzado com a jornada do
# CRM (leads atribuídos por CTWA → consulta marcada → compareceu → cirurgia):
#   overview  → um card por anúncio, com gancho/corpo/CTA, taxas e diagnóstico
#   detail    → série diária, curva de retenção, quebras e ativos de um anúncio
#   assets    → ranking de ganchos, corpos e CTAs da conta (criativo dinâmico)
class Crm::CreativeAnalyticsService # rubocop:disable Metrics/ClassLength
  RATE_KEYS = %w[hook_rate hold_rate link_ctr conv_rate].freeze
  SORTS = {
    'spend' => ->(r) { -r[:totals]['spend'].to_f },
    'hook' => ->(r) { -(r[:rates]['hook_rate'] || -1) },
    'hold' => ->(r) { -(r[:rates]['hold_rate'] || -1) },
    'ctr' => ->(r) { -(r[:rates]['link_ctr'] || -1) },
    'conversations' => ->(r) { -r[:totals]['conversations'].to_f },
    'cost' => ->(r) { r[:rates]['cost_conversation'] || Float::INFINITY },
    'leads' => ->(r) { -r[:funnel][:leads] },
    'surgeries' => ->(r) { [-r[:funnel][:surgeries], -r[:funnel][:booked]] }
  }.freeze

  def initialize(account:, since_date:, until_date:)
    @account = account
    @since_date = since_date
    @until_date = until_date
  end

  # ── Visão geral ───────────────────────────────────────────────────────────
  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
  def overview(campaign_id: nil, format: nil, status: nil, query: nil, sort: 'spend')
    creatives = Crm::AdCreative.where(account_id: @account.id).with_attached_thumbnail.for_campaign(campaign_id)
    creatives = creatives.where(format: format) if format.present?
    rows = creatives.map { |c| row_for(c, daily_by_ad[c.ad_id] || []) }
    rows = rows.select { |r| r[:totals]['spend'].to_f.positive? || r[:funnel][:leads].positive? } unless status == 'all'
    rows = rows.select { |r| r[:status] == 'ACTIVE' } if status == 'active'
    rows = rows.select { |r| matches_query?(r, query) } if query.present?

    averages = averages_for(rows)
    rows.each do |r|
      r[:diagnosis] = diagnosis_for(r, averages)
      r[:spark] = spark_for(r[:creative].ad_id)
      r[:prev] = prev_for(r[:creative].ad_id)
    end
    mark_champions(rows)
    rows.sort_by!(&(SORTS[sort] || SORTS['spend']))

    {
      rows: rows.map { |r| serialize_row(r) },
      totals: totals_for(rows), averages: averages,
      campaigns: campaigns_list, campaign_stats: campaign_stats, formats: formats_count,
      daily: account_daily, prev_daily: account_daily(prev_daily_by_ad), prev_totals: prev_totals_for(rows),
      targets: targets, data_since: data_since,
      period_days: period_days
    }
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
  # rubocop:enable Metrics/AbcSize

  # ── Um anúncio a fundo ────────────────────────────────────────────────────
  def detail(ad_id) # rubocop:disable Metrics/AbcSize
    creative = Crm::AdCreative.with_attached_thumbnail.find_by!(account_id: @account.id, ad_id: ad_id.to_s)
    list = daily_by_ad[creative.ad_id] || []
    row = row_for(creative, list)
    averages = averages_for(all_rows)
    row[:diagnosis] = diagnosis_for(row, averages)
    row[:prev] = prev_for(creative.ad_id)
    row[:spark] = spark_for(creative.ad_id)
    serialize_row(row).merge(
      averages: averages, targets: targets,
      daily: daily_series(list),
      halves: halves_for(list),
      summary: breakdown('summary', creative.ad_id)[:rows]&.first,
      placements: breakdown('placement', creative.ad_id),
      age_gender: breakdown('age_gender', creative.ad_id),
      assets: creative.dynamic? ? assets_for(creative.ad_id) : nil
    )
  end

  # campeões do recorte: menor custo por conversa, melhor gancho, corpo, CTA e conversa
  CHAMPION_KEYS = { cost: ['cost_conversation', :min], hook: ['hook_rate', :max], hold: ['hold_rate', :max],
                    cta: ['link_ctr', :max], conv: ['conv_rate', :max],
                    # v2 (item 177): o que vale dinheiro — ROAS, CAC (custo por cirurgia) e % de agendamento
                    roas: ['roas', :max], cac: ['cost_surgery', :min], booking: ['booking_rate', :max] }.freeze
  # jornada mínima para disputar os campeões de dinheiro (evita campeão com 1 lead)
  CHAMPION_FUNNEL_MIN = { roas: [:surgeries, 1], cac: [:surgeries, 1], booking: [:leads, 5] }.freeze

  def mark_champions(rows) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows.each { |r| r[:champion_of] = [] }
    eligible = rows.select { |r| r[:totals]['impressions'].to_f >= 500 }
    CHAMPION_KEYS.each do |key, (metric, dir)|
      pool = eligible.select { |r| r[:rates][metric] }
      pool = pool.select { |r| r[:totals]['conversations'].to_f >= 5 } if key == :cost
      rule = CHAMPION_FUNNEL_MIN[key]
      pool = pool.select { |r| r[:funnel][rule[0]].to_i >= rule[1] } if rule
      next if pool.size < 2

      best = dir == :min ? pool.min_by { |r| r[:rates][metric] } : pool.max_by { |r| r[:rates][metric] }
      best[:champion_of] << key.to_s
    end
  end

  # cartões de campanha (todas, independentemente do filtro) para escolher o que analisar
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Style/MultilineBlockChain
  def campaign_stats
    all_rows.group_by { |r| r[:creative].campaign_id }.map do |campaign_id, list|
      total = Crm::AdMetrics.sum(list.map { |r| r[:totals] })
      rates = Crm::AdMetrics.rates(total, video: total['plays_3s'].to_f.positive?)
      bands = list.filter_map { |r| worst_band(r) }.tally
      { id: campaign_id, name: list.first[:creative].campaign_name || 'Sem campanha', ads: list.size,
        spend: total['spend'], impressions: total['impressions'].to_i, conversations: total['conversations'].to_i,
        cost_conversation: rates['cost_conversation'], link_ctr: rates['link_ctr'], hook_rate: rates['hook_rate'],
        leads: list.sum { |r| r[:funnel][:leads] }, surgeries: list.sum { |r| r[:funnel][:surgeries] },
        bands: { 'bom' => bands['bom'].to_i, 'atencao' => bands['atencao'].to_i, 'ruim' => bands['ruim'].to_i } }
    end.sort_by { |c| -c[:spend].to_f }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Style/MultilineBlockChain

  def worst_band(row)
    bands = diagnosis_for(row, averages_for(all_rows))[:bands].values.compact
    return nil if bands.empty?
    return 'ruim' if bands.include?('ruim')
    return 'atencao' if bands.include?('atencao')

    'bom'
  end

  # campeões de peça (criativo dinâmico) mês a mês — chamadas à Meta com cache de 6 h
  def assets_history(months: 6)
    return [] unless Crm::AdCreative.exists?(account_id: @account.id, format: 'dynamic')

    first = Crm::AdInsight.where(account_id: @account.id).minimum(:date)
    return [] unless first

    month = Date.current.beginning_of_month
    list = []
    months.times do
      break if month < first.beginning_of_month

      since = [month, first].max
      until_d = [month.end_of_month, Date.current].min
      list << { month: month.iso8601, label: "#{Crm::CreativeRecords::MONTHS_PT[month.month - 1]}/#{month.year}" }
              .merge(%w[title body call_to_action].index_with { |k| top_asset("#{k}_asset", since, until_d) })
      month = month.prev_month
    end
    list
  end

  def top_asset(kind, since, until_d)
    rows = Crm::AdBreakdownService.new(account: @account, since_date: since, until_date: until_d, kind: kind).call[:rows] || []
    best = rows.select { |r| r[:conversations].to_i.positive? }.max_by { |r| r[:conversations] }
    best&.slice(:label, :conversations, :cost_conversation, :link_ctr, :impressions)
  end

  # 🎬 item 181: o que os VÍDEOS falam, ranqueado pelo que cada parte tem de
  # provar — gancho pela taxa de parada, corpo pela retenção, CTA falado pela
  # conversa por clique — no período da tela (só vídeos com transcrição)
  def video_assets
    rows = all_rows.select { |r| r[:creative].transcript_done? && r[:totals]['impressions'].to_f >= 300 }
    {
      hooks: video_part_rows(rows, :hook, 'hook_rate'),
      bodies: video_part_rows(rows, :body, 'hold_rate'),
      ctas: video_part_rows(rows, :video_cta, 'conv_rate'),
      transcribed: Crm::AdCreative.where(account_id: @account.id, format: 'video')
                                  .where("creative -> 'transcript' ->> 'status' = 'done'").count,
      videos: Crm::AdCreative.where(account_id: @account.id, format: 'video').count
    }
  end

  def video_part_rows(rows, part, metric)
    list = rows.filter_map { |r| video_row(r, part, metric) }
    list.sort_by { |row| -row[:value] }.first(12)
  end

  def video_row(row, part, metric)
    creative = row[:creative]
    text = creative.public_send(part)
    value = row[:rates][metric]
    return nil if text.blank? || value.nil?

    { ad_id: creative.ad_id, ad_name: creative.ad_name, text: text, angle: creative.transcript['angle'], value: value,
      metric: metric, impressions: row[:totals]['impressions'].to_i, conversations: row[:totals]['conversations'].to_i,
      cost_conversation: row[:rates]['cost_conversation'], thumbnail_url: creative.thumbnail_src }
  end

  # ── Gancho / corpo / CTA como ativos (conta inteira) ──────────────────────
  def assets_for(ad_id = nil)
    {
      titles: breakdown('title_asset', ad_id),
      bodies: breakdown('body_asset', ad_id),
      ctas: breakdown('call_to_action_asset', ad_id),
      dynamic_ads: Crm::AdCreative.where(account_id: @account.id, format: 'dynamic').count,
      video: video_assets
    }
  end

  private

  def breakdown(kind, ad_id)
    Crm::AdBreakdownService.new(account: @account, since_date: @since_date, until_date: @until_date,
                                kind: kind, ad_id: ad_id).call
  end

  # ── Dados base ────────────────────────────────────────────────────────────
  def daily_by_ad
    @daily_by_ad ||= Crm::AdInsight.where(account_id: @account.id).between(@since_date, @until_date)
                                   .order(:date).pluck(:ad_id, :date, :metrics)
                                   .group_by(&:first)
                                   .transform_values { |list| list.map { |_id, date, m| m.merge('date' => date) } }
  end

  def period_days
    (@until_date - @since_date).to_i + 1
  end

  def prev_range
    [@since_date - period_days, @since_date - 1]
  end

  def prev_daily_by_ad
    @prev_daily_by_ad ||= Crm::AdInsight.where(account_id: @account.id).between(*prev_range)
                                        .order(:date).pluck(:ad_id, :date, :metrics)
                                        .group_by(&:first)
                                        .transform_values { |list| list.map { |_id, date, m| m.merge('date' => date) } }
  end

  # o mesmo anúncio no período anterior de igual tamanho (para as setas ▲▼)
  def prev_for(ad_id)
    list = prev_daily_by_ad[ad_id] || []
    return nil if list.empty?

    total = Crm::AdMetrics.sum(list)
    rates = Crm::AdMetrics.rates(total, video: total['plays_3s'].to_f.positive?)
    { spend: total['spend'], impressions: total['impressions'].to_i, conversations: total['conversations'].to_i,
      link_ctr: rates['link_ctr'], hook_rate: rates['hook_rate'], hold_rate: rates['hold_rate'],
      conv_rate: rates['conv_rate'], cost_conversation: rates['cost_conversation'] }
  end

  def prev_totals_for(rows)
    ids = rows.map { |r| r[:creative].ad_id }
    lists = prev_daily_by_ad.slice(*ids).values
    return nil if lists.empty?

    total = Crm::AdMetrics.sum(lists.flatten)
    rates = Crm::AdMetrics.rates(total, video: total['plays_3s'].to_f.positive?)
    { spend: total['spend'], impressions: total['impressions'].to_i, conversations: total['conversations'].to_i,
      link_ctr: rates['link_ctr'], hook_rate: rates['hook_rate'], hold_rate: rates['hold_rate'],
      cost_conversation: rates['cost_conversation'] }
  end

  def targets
    @targets ||= Crm::CreativeTargets.for(@account)
  end

  def all_rows
    @all_rows ||= Crm::AdCreative.where(account_id: @account.id).with_attached_thumbnail
                                 .map { |c| row_for(c, daily_by_ad[c.ad_id] || []) }
                                 .select { |r| r[:totals]['spend'].to_f.positive? }
  end

  def data_since
    Crm::AdInsight.where(account_id: @account.id).minimum(:date)
  end

  def row_for(creative, list)
    totals = Crm::AdMetrics.sum(list)
    funnel = funnel_for(creative.ad_id)
    {
      creative: creative, status: creative.effective_status, totals: totals,
      rates: Crm::AdMetrics.rates(totals, video: video_like?(creative, totals))
                           .merge(Crm::AdFunnel.rates(funnel, totals['spend']).stringify_keys),
      funnel: funnel, days: list.size
    }
  end

  def video_like?(creative, totals)
    creative.video? || creative.dynamic? || totals['plays_3s'].to_f.positive?
  end

  def matches_query?(row, query)
    q = query.to_s.downcase
    c = row[:creative]
    [c.ad_name, c.hook, c.body, c.campaign_name, c.adset_name].compact.any? { |t| t.downcase.include?(q) }
  end

  # ── Jornada do CRM por anúncio (mesma régua do relatório de anúncios) ─────
  def funnel_for(ad_id)
    funnels[ad_id] || { leads: 0, booked: 0, attended: 0, surgeries: 0, revenue: 0.0 }
  end

  def funnels
    @funnels ||= Crm::AdFunnel.by_ad(@account, @since_date, @until_date, conversion_stage_ids: conversion_stage_ids)
  end

  def conversion_stage_ids
    @conversion_stage_ids ||= Crm::AdFunnel.stage_ids(@account)
  end

  # ── Médias da conta (ponderadas por impressão) e diagnóstico ─────────────
  def averages_for(rows)
    total = Crm::AdMetrics.sum(rows.pluck(:totals))
    video_total = Crm::AdMetrics.sum(rows.select { |r| r[:rates]['hook_rate'] }.pluck(:totals))
    video_rates = Crm::AdMetrics.rates(video_total, video: true)
    all_rates = Crm::AdMetrics.rates(total, video: false)
    funnel_rates = Crm::AdFunnel.rates(Crm::AdFunnel.sum(rows.pluck(:funnel)), total['spend']).stringify_keys
    { 'hook_rate' => video_rates['hook_rate'], 'hold_rate' => video_rates['hold_rate'],
      'retention' => video_rates['retention'],
      'link_ctr' => all_rates['link_ctr'], 'conv_rate' => all_rates['conv_rate'],
      'cost_conversation' => all_rates['cost_conversation'], 'cpm' => all_rates['cpm'] }.merge(funnel_rates)
  end

  def vs_avg_for(value, average)
    return nil if value.nil? || average.nil? || average.zero?

    ratio = value / average
    return 'acima' if ratio >= 1.15
    return 'abaixo' if ratio <= 0.85

    'na_media'
  end

  def pct(value, digits = 1)
    return '—' if value.nil?

    "#{format("%.#{digits}f", value * 100).tr('.', ',')}%"
  end

  def money(value)
    "R$ #{format('%.2f', value.to_f).tr('.', ',')}"
  end

  # Leitura em uma frase a partir dos PARÂMETROS (bom/atenção/ruim) — o que
  # está fora do lugar e o que fazer — mais a posição contra a média da conta.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
  def diagnosis_for(row, averages)
    rates = row[:rates]
    t = targets
    bands = {
      hook: Crm::CreativeTargets.band('hook_rate', rates['hook_rate'], t),
      hold: Crm::CreativeTargets.band('hold_rate', rates['hold_rate'], t),
      cta: Crm::CreativeTargets.band('link_ctr', rates['link_ctr'], t),
      conv: Crm::CreativeTargets.band('conv_rate', rates['conv_rate'], t),
      cost: Crm::CreativeTargets.band('cost_conversation', rates['cost_conversation'], t)
    }
    vs_avg = {
      hook: vs_avg_for(rates['hook_rate'], averages['hook_rate']),
      hold: vs_avg_for(rates['hold_rate'], averages['hold_rate']),
      cta: vs_avg_for(rates['link_ctr'], averages['link_ctr']),
      conv: vs_avg_for(rates['conv_rate'], averages['conv_rate'])
    }
    fatigue = fatigue?(row)
    focus, text =
      if row[:totals]['impressions'].to_f < 500
        ['esperar', 'Poucas impressões ainda: espere mais dados antes de decidir.']
      elsif bands[:hook] == 'ruim'
        ['gancho', "Gancho abaixo do parâmetro (parada #{pct(rates['hook_rate'])}, bom é ≥ #{pct(t['hook_rate']['good'], 0)}): " \
                   'poucos param nos 3 primeiros segundos. Troque a abertura: primeira frase e primeira imagem.']
      elsif bands[:hold] == 'ruim'
        ['corpo', "Gancho segura (parada #{pct(rates['hook_rate'])}) mas o corpo perde (retenção #{pct(rates['hold_rate'])}, " \
                  "bom é ≥ #{pct(t['hold_rate']['good'], 0)}): mexa nos 5 a 10 segundos depois do gancho."]
      elsif bands[:cta] == 'ruim'
        ['cta', "#{rates['hook_rate'] ? 'Assistem' : 'Veem'} mas não clicam (CTR #{pct(rates['link_ctr'], 2)}, bom é ≥ " \
                "#{pct(t['link_ctr']['good'], 1)}): reforce a oferta e o botão no fim."]
      elsif bands[:conv] == 'ruim'
        ['conversa', "Clicam (CTR #{pct(rates['link_ctr'], 2)}) mas não conversam (#{pct(rates['conv_rate'])} por clique, bom é ≥ " \
                     "#{pct(t['conv_rate']['good'], 0)}): revise a primeira mensagem do WhatsApp e o alinhamento anúncio → atendimento."]
      elsif bands[:cost] == 'ruim'
        ['publico', "Nenhuma peça está ruim, mas o custo por conversa passou do parâmetro (#{money(rates['cost_conversation'])}, " \
                    "bom é ≤ #{money(t['cost_conversation']['good'])}): teste público, posicionamento ou orçamento."]
      elsif bands.values.compact.all?('bom')
        ['escalar', 'Todos os parâmetros no verde: escale com cautela e vigie a frequência.']
      else
        weak = bands.select { |_k, v| v == 'atencao' }.keys
        names = { hook: 'gancho', hold: 'corpo', cta: 'CTA', conv: 'conversa', cost: 'custo por conversa' }
        [weak.first.to_s, "Na zona de atenção em #{weak.map { |k| names[k] }.join(', ')}: vale testar variações de " \
                          "#{names[weak.first]} para chegar ao verde."]
      end
    text += ' Sinal de fadiga: o CTR caiu na segunda metade do período, hora de renovar o criativo.' if fatigue
    { bands: bands, vs_avg: vs_avg, fatigue: fatigue, focus: focus, text: text }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength

  # fadiga = o anúncio segue entregando (2ª metade com ≥ 40 % das impressões
  # da 1ª) e o CTR da 2ª metade caiu para ≤ 75 % da 1ª (período ≥ 14 dias)
  def fatigue?(row)
    list = daily_by_ad[row[:creative].ad_id] || []
    return false if list.size < 14

    first, last = halves_for(list).values_at(:first, :last)
    return false unless first[:link_ctr].to_f.positive? && last[:impressions].to_f >= first[:impressions].to_f * 0.4

    last[:link_ctr].to_f <= first[:link_ctr].to_f * 0.75
  end

  def halves_for(list)
    half = list.size / 2
    first = Crm::AdMetrics.sum(list.first(half))
    last = Crm::AdMetrics.sum(list.drop(half))
    { first: half_json(first), last: half_json(last) }
  end

  def half_json(total)
    rates = Crm::AdMetrics.rates(total, video: total['plays_3s'].to_f.positive?)
    { spend: total['spend'], impressions: total['impressions'].to_i, link_ctr: rates['link_ctr'],
      hook_rate: rates['hook_rate'], frequency: total['frequency'], conversations: total['conversations'].to_i }
  end

  # ── Séries ────────────────────────────────────────────────────────────────
  def spark_for(ad_id)
    list = (daily_by_ad[ad_id] || []).last(30)
    { labels: list.map { |m| m['date'].strftime('%d/%m') },
      ctr: list.map { |m| m['impressions'].to_f.positive? ? (m['link_clicks'].to_f / m['impressions'] * 100).round(2) : 0 },
      spend: list.map { |m| m['spend'].to_f.round(2) } }
  end

  def daily_series(list) # rubocop:disable Metrics/AbcSize
    list.map do |m|
      video = m['plays_3s'].to_f.positive?
      rates = Crm::AdMetrics.rates(m, video: video)
      { date: m['date'].iso8601, label: m['date'].strftime('%d/%m'), spend: m['spend'].to_f, impressions: m['impressions'].to_i,
        reach: m['reach'].to_i, link_clicks: m['link_clicks'].to_i, conversations: m['conversations'].to_i,
        plays_3s: m['plays_3s'].to_i, thruplay: m['thruplay'].to_i, frequency: m['frequency'].to_f,
        link_ctr: rates['link_ctr'], hook_rate: rates['hook_rate'], hold_rate: rates['hold_rate'],
        cost_conversation: rates['cost_conversation'] }
    end
  end

  def account_daily(source = daily_by_ad)
    by_date = source.values.flatten.group_by { |m| m['date'] }.sort.to_h
    by_date.map do |date, list|
      total = Crm::AdMetrics.sum(list)
      { date: date.iso8601, label: date.strftime('%d/%m'), spend: total['spend'], impressions: total['impressions'].to_i,
        link_clicks: total['link_clicks'].to_i, conversations: total['conversations'].to_i,
        link_ctr: total['impressions'].positive? ? (total['link_clicks'] / total['impressions']).round(4) : 0 }
    end
  end

  # ── Totais, listas e serialização ─────────────────────────────────────────
  def totals_for(rows)
    total = Crm::AdMetrics.sum(rows.pluck(:totals))
    funnel = rows.pluck(:funnel)
    total.merge(
      'ads' => rows.size,
      'leads' => funnel.sum { |f| f[:leads] }, 'booked' => funnel.sum { |f| f[:booked] },
      'attended' => funnel.sum { |f| f[:attended] }, 'surgeries' => funnel.sum { |f| f[:surgeries] },
      'revenue' => funnel.sum { |f| f[:revenue] }.round(2)
    )
  end

  def campaigns_list
    Crm::AdCreative.where(account_id: @account.id).where.not(campaign_id: nil)
                   .group(:campaign_id, :campaign_name).count
                   .map { |(id, name), n| { id: id, name: name, ads: n } }
                   .sort_by { |c| c[:name].to_s }
  end

  def formats_count
    Crm::AdCreative.where(account_id: @account.id).group(:format).count
  end

  # rubocop:disable Metrics/AbcSize
  def serialize_row(row)
    c = row[:creative]
    {
      ad_id: c.ad_id, ad_name: c.ad_name, adset_name: c.adset_name, campaign_id: c.campaign_id,
      campaign_name: c.campaign_name, status: c.effective_status, format: c.format, format_label: c.format_label,
      hook: c.hook, body: c.body, cta: c.cta, cta_label: Crm::AdCreativeParser.cta_label(c.cta),
      # 🎬 item 181: de onde vem o texto (video | ad) + o que o vídeo fala
      text_source: c.text_source, video_cta: c.video_cta, ad_hook: c.ad_hook, ad_body: c.ad_body,
      transcript: c.transcript.slice('status', 'error', 'text', 'angle', 'transcribed_at'),
      description: c.creative['description'], thumbnail_url: c.thumbnail_src, thumbnail_stored: c.thumbnail_stored?,
      permalink: c.creative['permalink'], video_id: c.creative['video_id'],
      titles: c.creative['titles'] || [], bodies: c.creative['bodies'] || [], ctas: c.creative['ctas'] || [],
      days: row[:days], totals: row[:totals].except('actions'), rates: row[:rates], funnel: row[:funnel],
      diagnosis: row[:diagnosis], spark: row[:spark], prev: row[:prev], champion_of: row[:champion_of] || []
    }
  end
  # rubocop:enable Metrics/AbcSize
end
