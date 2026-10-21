# 👀 LEITURA UNIFICADA Meta + Google do Agente de Campanhas (item 352), num
# intervalo de datas, em três níveis: campanha → conjunto → anúncio (Meta) e
# campanha (Google; o conjunto/anúncio do Google vem quando ligarmos a API do
# Google Ads).
#
# De onde vem cada número (filosofia: revelar o dado pelas conexões):
#   Meta    gasto/exibições/cliques/conversas = foto diária por anúncio
#           (cevico_ad_insights); leads = clique no anúncio → WhatsApp
#           (meta_ads.source_id = anúncio) + leads das PÁGINAS com utm da Meta
#           (page_ads.source = meta_ads; o utm_content com o nome do anúncio
#           liga ao anúncio; sem ele, fica na campanha)
#   Google  gasto/cliques/impressões = foto diária por campanha (GA4 →
#           cevico_campaign_days); leads = page_ads.source = google_ads, ligados
#           à campanha pelo utm_id ({campaignid}) ou pelo nome (utm_campaign)
#   CRM     agendou/compareceu/fechou/operou/receita = Crm::AdFunnelSteps
#           (CRM × Agenda × Oftalmofácil), os mesmos degraus dos Criativos
# O que não encontrou campanha aparece como "sem rastreio" — dinheiro ou lead
# que ainda não dá para ligar um ao outro.
class Cevico::CampaignAgent::Reader # rubocop:disable Metrics/ClassLength
  ROW = Cevico::CampaignAgent::Row
  ID_LOOKBACK = 120.days
  UNTRACKED = '(sem rastreio de campanha)'.freeze

  attr_reader :since_date, :until_date, :goal

  def initialize(account:, since_date:, until_date:, goal: 'booked', channels: %w[meta google])
    @account = account
    @since_date = since_date
    @until_date = until_date
    @goal = goal
    @channels = channels
  end

  # { campaigns: [...], flat: [...], totals: { 'all' =>, 'meta' =>, 'google' => }, untracked: {...}, time_to_book: {...} }
  def call
    campaigns = []
    campaigns.concat(meta_campaigns) if @channels.include?('meta')
    campaigns.concat(google_campaigns) if @channels.include?('google')
    campaigns = campaigns.sort_by { |c| [-c['spend'].to_f, -c['leads'].to_f] }
    { campaigns: campaigns, flat: flatten(campaigns), totals: totals(campaigns), time_to_book: time_to_book }
  end

  # totais por canal e geral (linhas fechadas, com taxas)
  def totals(campaigns = nil)
    campaigns ||= call[:campaigns]
    out = {}
    (%w[all] + @channels).each do |ch|
      list = ch == 'all' ? campaigns : campaigns.select { |c| c['channel'] == ch }
      out[ch] = finish(sum_rows(list), 'channel', ch == 'all' ? 'Tudo' : ch, ch)
    end
    out
  end

  # ── dia a dia (gráficos da tela, item 358c — 21/10) ────────────────────
  # gasto, leads e agendamentos por DIA e por canal no período. O agendamento
  # é contado no dia em que o lead CHEGOU (coorte), o mesmo critério dos totais:
  # "dos que chegaram neste dia, quantos marcaram".
  def daily # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    dates = (@since_date..@until_date).to_a
    spend = { 'meta' => Hash.new(0.0), 'google' => Hash.new(0.0) }
    if @channels.include?('meta')
      Crm::AdInsight.where(account_id: @account.id).between(@since_date, @until_date).group(:date)
                    .sum(Arel.sql("COALESCE((metrics->>'spend')::numeric, 0)")).each { |d, v| spend['meta'][d] = v.to_f }
    end
    if @channels.include?('google')
      Crm::CampaignDay.google.where(account_id: @account.id).between(@since_date, @until_date).group(:date).sum(:spend)
                      .each { |d, v| spend['google'][d] = v.to_f }
    end
    leads = { 'meta' => meta_lead_dates, 'google' => google_lead_dates }
    booked_at = first_booked_at(leads.values.flat_map(&:keys), Crm::AdFunnelSteps.stage_ids_for(@account)[:booked])
    per = %w[meta google].to_h do |ch|
      by_day = Hash.new(0)
      booked_by_day = Hash.new(0)
      leads[ch].each do |cid, at|
        d = at.to_date
        by_day[d] += 1
        booked_by_day[d] += 1 if booked_at[cid]
      end
      [ch, { 'spend' => dates.map { |d| spend[ch][d].round(2) }, 'leads' => dates.map { |d| by_day[d] },
             'booked' => dates.map { |d| booked_by_day[d] } }]
    end
    per['all'] = %w[spend leads booked].index_with do |k|
      dates.each_index.map { |i| (per['meta'][k][i] + per['google'][k][i]).round(2) }
    end
    { 'labels' => dates.map { |d| d.strftime('%d/%m') }, 'dates' => dates.map(&:iso8601) }.merge(per)
  end

  private

  # ── META ───────────────────────────────────────────────────────────────
  def meta_campaigns # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    ad_rows = meta_ad_rows
    by_adset = ad_rows.group_by { |r| r['parent_id'] }
    adsets = by_adset.map do |adset_id, ads|
      first = ads.first
      row = finish(sum_rows(ads), 'adset', first['adset_name'], 'meta', id: adset_id, parent_id: first['campaign_id'])
      row.merge('campaign_id' => first['campaign_id'], 'campaign_name' => first['campaign_name'],
                'status' => ads.any? { |a| a['status'] == 'ACTIVE' } ? 'ACTIVE' : (first['adset_status'] || first['status']),
                'children' => ads.sort_by { |a| -a['spend'].to_f })
    end
    by_campaign = adsets.group_by { |r| r['parent_id'] }
    campaigns = by_campaign.map do |campaign_id, sets|
      first = sets.first
      row = sum_rows(sets)
      ROW.add_funnel!(row, meta_page_funnels[:campaign][simple(first['campaign_name'])]) if campaign_id.present?
      finish(row, 'campaign', first['campaign_name'], 'meta', id: campaign_id, parent_id: nil)
        .merge('status' => sets.any? { |s| s['status'] == 'ACTIVE' } ? 'ACTIVE' : 'PAUSED', 'children' => sets.sort_by { |s| -s['spend'].to_f })
    end
    campaigns << meta_untracked_row if meta_page_funnels[:untracked].present?
    campaigns
  end

  def meta_ad_rows # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @meta_ad_rows ||= begin
      sums = meta_insights.transform_values { |list| Crm::AdMetrics.sum(list) }
      ids = (sums.keys + meta_ctwa.keys + meta_page_funnels[:ad].keys).uniq
      creatives = Crm::AdCreative.where(account_id: @account.id, ad_id: ids).index_by(&:ad_id)
      ids.map do |ad_id|
        c = creatives[ad_id]
        total = sums[ad_id] || {}
        row = ROW.from_meta(total, meta_ctwa[ad_id])
        ROW.add_funnel!(row, meta_page_funnels[:ad][ad_id])
        video = c ? c.format == 'video' || total['plays_3s'].to_f.positive? : nil
        finish(row, 'ad', c&.ad_name || "Anúncio #{ad_id}", 'meta', id: ad_id, parent_id: c&.adset_id.presence || 'sem-conjunto', video: video)
          .merge('campaign_id' => c&.campaign_id, 'campaign_name' => c&.campaign_name || 'Sem campanha',
                 'adset_name' => c&.adset_name || 'Sem conjunto', 'status' => c&.effective_status, 'format' => c&.format,
                 'thumbnail' => c&.creative&.dig('thumbnail_url'), 'first_day' => meta_first_day[ad_id]&.iso8601)
      end
    end
  end

  def meta_insights
    @meta_insights ||= Crm::AdInsight.where(account_id: @account.id).between(@since_date, @until_date)
                                     .pluck(:ad_id, :metrics).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  # primeiro dia com número de cada anúncio (para saber se é NOVO — fase de aprendizado)
  def meta_first_day
    @meta_first_day ||= Crm::AdInsight.where(account_id: @account.id, ad_id: meta_insights.keys).group(:ad_id).minimum(:date)
  end

  # leads do clique no anúncio → WhatsApp (CTWA), por anúncio
  def meta_ctwa
    @meta_ctwa ||= Crm::AdFunnel.by_ad(@account, @since_date, @until_date)
  end

  # leads das páginas com utm da Meta: { ad: { ad_id => funnel }, campaign: { nome simples => funnel }, untracked: funnel }
  def meta_page_funnels # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @meta_page_funnels ||= begin
      leads = page_leads('meta_ads')
      ads_by_name = Crm::AdCreative.where(account_id: @account.id).pluck(:ad_name, :ad_id, :campaign_name)
      name_index = ads_by_name.to_h { |name, id, _| [simple(name), id] }
      campaign_names = ads_by_name.to_set { |_, _, cn| simple(cn) }
      ad_groups = Hash.new { |h, k| h[k] = [] }
      campaign_groups = Hash.new { |h, k| h[k] = [] }
      untracked = []
      leads.each do |cid, campaign, content, _utm_id|
        ad_id = name_index[simple(content)] || (content.to_s.match?(/\A\d{8,}\z/) ? content.to_s : nil)
        if ad_id
          ad_groups[ad_id] << cid
        elsif campaign_names.include?(simple(campaign))
          campaign_groups[simple(campaign)] << cid
        else
          untracked << [cid, campaign]
        end
      end
      steps = steps_for(leads.map(&:first))
      { ad: ad_groups.transform_values { |cids| Crm::AdFunnel.funnel_row(cids, steps) },
        campaign: campaign_groups.transform_values { |cids| Crm::AdFunnel.funnel_row(cids, steps) },
        untracked: untracked.any? ? Crm::AdFunnel.funnel_row(untracked.map(&:first), steps) : nil,
        untracked_names: untracked.map(&:last).compact_blank.tally }
    end
  end

  def meta_untracked_row
    row = ROW.add_funnel!(ROW.blank, meta_page_funnels[:untracked])
    names = meta_page_funnels[:untracked_names].sort_by { |_, n| -n }.first(3).map(&:first)
    finish(row, 'campaign', UNTRACKED, 'meta', id: 'meta-untracked', parent_id: nil)
      .merge('untracked' => true, 'children' => [], 'status' => nil,
             'note' => names.any? ? "utm_campaign visto: #{names.join(', ')}" : 'leads de página da Meta sem utm que case com um anúncio ou campanha')
  end

  # ── GOOGLE ─────────────────────────────────────────────────────────────
  def google_campaigns # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    days = Crm::CampaignDay.google.where(account_id: @account.id).between(@since_date, @until_date)
                           .group(:campaign_id)
                           .pluck(:campaign_id, Arel.sql('SUM(spend)'), Arel.sql('SUM(clicks)'), Arel.sql('SUM(impressions)'),
                                  Arel.sql('MAX(campaign_name)'))
    cost = days.to_h { |id, spend, clicks, imp, name| [id, { spend: spend.to_f, clicks: clicks.to_i, impressions: imp.to_i, name: name }] }
    funnels = google_funnels(cost)
    rows = (cost.keys | funnels[:by_id].keys).map do |id|
      c = cost[id] || { spend: 0, clicks: 0, impressions: 0, name: funnels[:names][id] }
      row = ROW.from_google(spend: c[:spend], clicks: c[:clicks], impressions: c[:impressions], funnel: funnels[:by_id][id])
      finish(row, 'campaign', c[:name].presence || "Campanha #{id}", 'google', id: id, parent_id: nil, video: false)
        .merge('status' => c[:spend].positive? ? 'ACTIVE' : 'PAUSED', 'children' => [], 'first_day' => google_first_day[id]&.iso8601)
    end
    rows << google_untracked_row(funnels) if funnels[:untracked].present?
    rows
  end

  def google_first_day
    @google_first_day ||= Crm::CampaignDay.google.where(account_id: @account.id).group(:campaign_id).minimum(:date)
  end

  # leads do Google (page_ads) ligados à campanha: pelo utm_id, pelo id mais visto
  # para aquele utm_campaign (Protocolos), ou pelo nome simplificado
  def google_funnels(cost) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    leads = page_leads('google_ads')
    by_simple_name = cost.to_h { |id, c| [simple(c[:name]), id] }
    groups = Hash.new { |h, k| h[k] = [] }
    untracked = []
    names = {}
    leads.each do |cid, campaign, _content, utm_id|
      id = utm_id.presence if utm_id.present? && cost.key?(utm_id)
      # anúncio que manda o ID da campanha no próprio utm_campaign (visto em produção 19/10)
      id ||= campaign.to_s if campaign.to_s.match?(/\A\d{6,}\z/) && cost.key?(campaign.to_s)
      id ||= ids_by_name[campaign]
      id ||= by_simple_name[simple(campaign)]
      if id
        groups[id] << cid
        names[id] ||= cost.dig(id, :name).presence || campaign
      else
        untracked << [cid, campaign]
      end
    end
    steps = steps_for(leads.map(&:first))
    { by_id: groups.transform_values { |cids| Crm::AdFunnel.funnel_row(cids, steps) }, names: names,
      untracked: untracked.any? ? Crm::AdFunnel.funnel_row(untracked.map(&:first), steps) : nil,
      untracked_names: untracked.map(&:last).compact_blank.tally }
  end

  def google_untracked_row(funnels)
    row = ROW.add_funnel!(ROW.blank, funnels[:untracked])
    names = funnels[:untracked_names].sort_by { |_, n| -n }.first(3).map(&:first)
    finish(row, 'campaign', UNTRACKED, 'google', id: 'google-untracked', parent_id: nil, video: false)
      .merge('untracked' => true, 'children' => [], 'status' => nil,
             'note' => names.any? ? "utm_campaign visto: #{names.join(', ')}" : 'leads do Google sem utm_campaign (anúncio sem sufixo de rastreio)')
  end

  # utm_campaign → ID da campanha mais visto nos Protocolos recentes (mesma regra do ROI por campanha)
  def ids_by_name
    @ids_by_name ||= begin
      pairs = @account.cevico_page_refs
                      .where(created_at: (@since_date - ID_LOOKBACK).beginning_of_day..@until_date.end_of_day)
                      .where("source_data ->> 'utm_id' IS NOT NULL AND source_data ->> 'campaign' <> ''")
                      .group(Arel.sql("source_data ->> 'campaign'"), Arel.sql("source_data ->> 'utm_id'")).count
      pairs.group_by { |(name, _id), _n| name }.transform_values { |list| list.max_by { |(_name, _id), n| n }.first.last }
    end
  end

  # ── CRM ────────────────────────────────────────────────────────────────
  # [[contact_id, campaign, content, utm_id]] dos leads que chegaram por página com aquela origem
  def page_leads(source)
    @page_leads ||= {}
    @page_leads[source] ||= @account.contacts
                                    .where("additional_attributes -> 'page_ads' ->> 'source' = ?", source)
                                    .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz >= ?", @since_date.beginning_of_day)
                                    .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz <= ?", @until_date.end_of_day)
                                    .pluck(:id, Arel.sql("additional_attributes -> 'page_ads' ->> 'campaign'"),
                                           Arel.sql("additional_attributes -> 'page_ads' ->> 'utm_content'"),
                                           Arel.sql("additional_attributes -> 'page_ads' ->> 'utm_id'"))
  end

  def steps_for(contact_ids)
    Crm::AdFunnelSteps.new(@account, contact_ids.uniq)
  end

  # ⏱️ terciário: mediana de dias entre o lead chegar e entrar na coluna de
  # agendamento (ou ser marcado na Agenda), por canal
  def time_to_book
    leads = { 'meta' => meta_lead_dates, 'google' => google_lead_dates }
    stage_ids = Crm::AdFunnelSteps.stage_ids_for(@account)[:booked]
    all_ids = leads.values.flat_map(&:keys)
    return {} if all_ids.empty?

    booked_at = first_booked_at(all_ids, stage_ids)
    leads.to_h do |ch, dates|
      days = dates.filter_map { |cid, at| booked_at[cid] && ((booked_at[cid].to_date - at.to_date).to_i) }
      [ch, { median_days: median(days), measured: days.size, leads: dates.size }]
    end.merge('all' => all_time_to_book(leads, booked_at))
  end

  def all_time_to_book(leads, booked_at)
    dates = leads.values.reduce({}, :merge)
    days = dates.filter_map { |cid, at| booked_at[cid] && ((booked_at[cid].to_date - at.to_date).to_i) }
    { median_days: median(days), measured: days.size, leads: dates.size }
  end

  def meta_lead_dates
    return {} unless @channels.include?('meta')

    ctwa = @account.contacts
                   .where("additional_attributes -> 'meta_ads' ->> 'source_id' IS NOT NULL")
                   .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz BETWEEN ? AND ?",
                          @since_date.beginning_of_day, @until_date.end_of_day)
                   .pluck(:id, Arel.sql("additional_attributes -> 'meta_ads' ->> 'captured_at'"))
    (ctwa + page_lead_dates('meta_ads')).to_h.transform_values { |at| Time.zone.parse(at.to_s) || @since_date }
  end

  def google_lead_dates
    return {} unless @channels.include?('google')

    page_lead_dates('google_ads').to_h.transform_values { |at| Time.zone.parse(at.to_s) || @since_date }
  end

  def page_lead_dates(source)
    @account.contacts
            .where("additional_attributes -> 'page_ads' ->> 'source' = ?", source)
            .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz BETWEEN ? AND ?",
                   @since_date.beginning_of_day, @until_date.end_of_day)
            .pluck(:id, Arel.sql("additional_attributes -> 'page_ads' ->> 'captured_at'"))
  end

  def first_booked_at(contact_ids, stage_ids) # rubocop:disable Metrics/AbcSize
    out = {}
    if stage_ids.present?
      cards = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }, contact_id: contact_ids).pluck(:id, :contact_id).to_h
      Crm::StageLog.where(crm_contact_id: cards.keys, stage_id: stage_ids).group(:crm_contact_id).minimum(:entered_at)
                   .each { |card_id, at| out[cards[card_id]] = [out[cards[card_id]], at].compact.min }
    end
    @account.tasks.where(task_type: 'consulta', contact_id: contact_ids).group(:contact_id).minimum(:created_at)
            .each { |cid, at| out[cid] = [out[cid], at].compact.min }
    out
  end

  def median(list)
    return nil if list.empty?

    sorted = list.sort
    mid = sorted.size / 2
    (sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0).round(1)
  end

  # ── montagem ───────────────────────────────────────────────────────────
  def sum_rows(rows)
    rows.each_with_object(ROW.blank) do |r, acc|
      ROW.add!(acc, r)
      acc['frequency'] = 0.0 # recalculada pelo alcance no finish
    end
  end

  def finish(row, level, name, channel, id: nil, parent_id: nil, video: nil) # rubocop:disable Metrics/ParameterLists
    ROW.finish(row, goal: @goal, video: video).merge('level' => level, 'name' => name.to_s, 'channel' => channel, 'id' => id.to_s,
                                                     'parent_id' => parent_id)
  end

  def flatten(campaigns)
    campaigns.flat_map do |c|
      [c.except('children')] + Array(c['children']).flat_map { |s| [s.except('children')] + Array(s['children']).map { |a| a.except('children') } }
    end
  end

  def simple(text)
    I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]/, '')
  end
end
