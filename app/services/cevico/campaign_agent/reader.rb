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
    campaigns.concat(seo_pages) if @channels.include?('seo')
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
      out[ch].merge!(seo_search_console_totals) if ch == 'seo'
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
    per['seo'] = seo_daily(dates) if @channels.include?('seo')
    { 'labels' => dates.map { |d| d.strftime('%d/%m') }, 'dates' => dates.map(&:iso8601) }.merge(per)
  end

  # dia a dia do orgânico: visitas e cliques no WhatsApp (tráfego das páginas) + leads/agendamentos
  def seo_daily(dates) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    traffic = @account.cevico_page_traffic.where(date: @since_date..@until_date).where.not(source: PAID_SOURCES)
                      .group(:date).pluck(:date, Arel.sql('SUM(views)'), Arel.sql('SUM(cta_clicks)')).to_h { |d, v, c| [d, [v.to_i, c.to_i]] }
    leads = organic_lead_dates
    booked_at = first_booked_at(leads.keys, Crm::AdFunnelSteps.stage_ids_for(@account)[:booked])
    by_day = Hash.new(0)
    booked_by_day = Hash.new(0)
    leads.each do |cid, at|
      d = at.to_date
      by_day[d] += 1
      booked_by_day[d] += 1 if booked_at[cid]
    end
    { 'spend' => dates.map { 0.0 }, 'views' => dates.map { |d| traffic.dig(d, 0).to_i }, 'cta' => dates.map { |d| traffic.dig(d, 1).to_i },
      'leads' => dates.map { |d| by_day[d] }, 'booked' => dates.map { |d| booked_by_day[d] } }
  end

  private

  # ── META ───────────────────────────────────────────────────────────────
  def meta_campaigns # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
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
    campaigns << team_row('meta') if team_row('meta')
    campaigns
  end

  # ── INFORMADO PELA EQUIPE (item 362) ────────────────────────────────────
  # pacientes sem carimbo automático cujo "como chegou" a equipe informou no
  # cadastro (Crm::LeadChannel): uma linha por canal, sem gasto próprio — o
  # gasto do canal já está nas campanhas; aqui entram leads, consultas e
  # cirurgias que antes ficavam invisíveis
  def team_row(channel) # rubocop:disable Metrics/MethodLength
    @team_rows ||= {}
    return @team_rows[channel] if @team_rows.key?(channel)

    keys = Crm::LeadChannel.keys_for(channel)
    cids = @account.contacts
                   .where("additional_attributes -> 'canal_origem' ->> 'key' IN (?)", keys)
                   .where("additional_attributes -> 'meta_ads' ->> 'source_id' IS NULL")
                   .where("COALESCE(additional_attributes -> 'page_ads' ->> 'source', '') NOT IN (?)", PAID_SOURCES)
                   .where("(additional_attributes -> 'canal_origem' ->> 'em')::timestamptz BETWEEN ? AND ?",
                          @since_date.beginning_of_day, @until_date.end_of_day)
                   .pluck(:id)
    @team_rows[channel] = if cids.empty?
                            nil
                          else
                            funnel = Crm::AdFunnel.funnel_row(cids, steps_for(cids))
                            row = ROW.add_funnel!(ROW.blank, funnel)
                            finish(row, 'campaign', Crm::AcquisitionChannel::TEAM_CAMPAIGN, channel, id: "#{channel}-team", parent_id: nil,
                                                                                                     video: false)
                              .merge('team' => true, 'children' => [], 'status' => nil,
                                     'note' => "pacientes cujo \"como chegou\" a equipe informou no cadastro: #{keys.map do |k|
                                       Crm::LeadChannel.label_for(k)
                                     end.join(', ')}")
                          end
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

  # ── SEO / ORGÂNICO (item 359, 21/10) ───────────────────────────────────
  # As páginas SEM anúncio pago, lidas como um canal: visita = "exibição",
  # clique no WhatsApp = "clique", e os leads carimbados pela página com origem
  # orgânica (Google orgânico, redes, busca, direto). Gasto = 0: a estrela-guia
  # não se aplica; o que vale são as taxas e os agendamentos. Por cima, o que o
  # Google conta no Search Console (cliques, impressões, posição) — a foto é de
  # uma janela fixa de 28 dias por página; os totais do período somam o diário.
  PAID_SOURCES = %w[google_ads meta_ads].freeze

  def seo_pages # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    traffic = @account.cevico_page_traffic.where(date: @since_date..@until_date).where.not(source: PAID_SOURCES)
                      .group(:cevico_page_id).pluck(:cevico_page_id, Arel.sql('SUM(views)'), Arel.sql('SUM(cta_clicks)'))
                      .to_h { |pid, v, c| [pid, { views: v.to_i, cta: c.to_i }] }
    leads = organic_page_leads
    steps = steps_for(leads.map(&:first))
    by_page = leads.group_by { |_, pid, _| pid }
    ids = (traffic.keys | by_page.keys).compact
    pages = @account.cevico_pages.where(id: ids).pluck(:id, :title, :slug, :emoji).to_h { |id, t, sl, e| [id, { title: t, slug: sl, emoji: e }] }
    gsc = seo_search_console_pages
    rows = (traffic.keys | by_page.keys).map do |pid|
      t = traffic[pid] || { views: 0, cta: 0 }
      funnel = by_page[pid] ? Crm::AdFunnel.funnel_row(by_page[pid].map(&:first), steps) : nil
      row = ROW.from_google(spend: 0, clicks: t[:cta], impressions: t[:views], funnel: funnel)
      name = pid.nil? ? 'Porta de entrada (hub)' : (pages.dig(pid, :title) || "Página #{pid}")
      finish(row, 'campaign', name, 'seo', id: pid.nil? ? 'hub' : "page-#{pid}", parent_id: nil, video: false)
        .merge('status' => 'ACTIVE', 'children' => [], 'page_id' => pid, 'slug' => pages.dig(pid, :slug), 'emoji' => pages.dig(pid, :emoji),
               'gsc' => gsc[pid])
    end
    rows = rows.sort_by { |r| [-r['leads'].to_f, -r['impressions'].to_f] }
    rows << team_row('organico').merge('channel' => 'seo', 'id' => 'seo-team') if team_row('organico')
    rows
  end

  # [[contato, página, origem]] dos leads que chegaram por página SEM anúncio pago
  def organic_page_leads
    organic_contacts.pluck(:id, Arel.sql("(additional_attributes -> 'page_ads' ->> 'page_id')::bigint"),
                           Arel.sql("additional_attributes -> 'page_ads' ->> 'source'"))
  end

  def organic_lead_dates
    organic_contacts.pluck(:id, Arel.sql("additional_attributes -> 'page_ads' ->> 'captured_at'"))
                    .to_h.transform_values { |at| Time.zone.parse(at.to_s) || @since_date }
  end

  def organic_contacts
    @account.contacts
            .where("additional_attributes -> 'page_ads' IS NOT NULL")
            .where("COALESCE(additional_attributes -> 'page_ads' ->> 'source', '') NOT IN (?)", PAID_SOURCES)
            .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz BETWEEN ? AND ?",
                   @since_date.beginning_of_day, @until_date.end_of_day)
  end

  def search_console
    @search_console ||= Cevico::SearchConsoleReport.new(@account).call
  rescue StandardError => e
    Rails.logger.warn "[CEVICO campanhas] Search Console indisponível: #{e.message}"
    @search_console = {}
  end

  # por página, a foto da janela fixa (28 dias) do Search Console
  def seo_search_console_pages
    (search_console[:pages] || []).each_with_object({}) do |p, h|
      h[p[:page_id]] = p.slice(:clicks, :impressions, :ctr, :position) if p[:page_id]
    end
  end

  # cliques e impressões do Google dentro do PERÍODO (a foto diária cobre ~56 dias)
  def seo_search_console_totals
    rows = (search_console[:daily] || []).select do |d, _, _|
      Date.parse(d.to_s).between?(@since_date, @until_date)
    rescue ArgumentError
      false
    end
    { 'gsc_clicks' => rows.sum { |_, c, _| c.to_i }, 'gsc_impressions' => rows.sum { |_, _, i| i.to_i }, 'gsc_days' => rows.size,
      'gsc_ready' => search_console[:ready] == true, 'gsc_window' => search_console[:window] }
  end

  # ── GOOGLE ─────────────────────────────────────────────────────────────
  def google_campaigns # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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
    rows << team_row('google') if team_row('google')
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
  def time_to_book # rubocop:disable Metrics/AbcSize
    leads = { 'meta' => meta_lead_dates, 'google' => google_lead_dates }
    leads['seo'] = organic_lead_dates if @channels.include?('seo')
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
