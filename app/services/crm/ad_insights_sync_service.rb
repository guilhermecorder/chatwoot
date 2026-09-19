# Sincroniza da Marketing API da Meta (item 172 — Central de Criativos):
#   1) anúncios + criativo (gancho/corpo/CTA/miniatura/formato) → cevico_ad_creatives
#   2) métricas por anúncio POR DIA (vídeo, cliques, conversas) → cevico_ad_insights
# Roda de madrugada (Crm::AdInsightsSyncJob) e pelo botão "Atualizar dados".
# Estado em meta_ads_config['creatives_sync'] (synced_at, running_since, last_error,
# progress {done,total,since,until} durante a carga longa, recovered, history_days).
class Crm::AdInsightsSyncService
  INSIGHT_FIELDS = %w[
    ad_id ad_name adset_id adset_name campaign_id campaign_name
    spend impressions reach frequency clicks inline_link_clicks actions cost_per_action_type
    video_play_actions video_thruplay_watched_actions video_p25_watched_actions video_p50_watched_actions
    video_p75_watched_actions video_p100_watched_actions video_avg_time_watched_actions
    video_continuous_2_sec_watched_actions
  ].freeze
  BASIC_FIELDS = %w[ad_id ad_name adset_id adset_name campaign_id campaign_name
                    spend impressions reach frequency clicks inline_link_clicks actions cost_per_action_type].freeze
  AD_FIELDS = 'id,name,effective_status,adset{id,name},campaign{id,name},' \
              'creative{id,name,title,body,call_to_action_type,thumbnail_url,image_url,video_id,' \
              'instagram_permalink_url,object_story_spec,asset_feed_spec}'.freeze
  DEFAULT_DAYS = 3      # a Meta reprocessa os últimos dias → refaz sempre
  FIRST_SYNC_DAYS = 90
  MAX_DAYS = 1125       # 37 meses: até onde a Meta guarda os números por anúncio
  WINDOW_DAYS = 90      # a carga longa vai em janelas (pedido grande a Meta recusa)
  MIN_MANUAL_GAP = 10.minutes
  # /ads sem filtro esconde apagados e arquivados; pedimos TODOS os status
  ALL_STATUSES = %w[ACTIVE PAUSED DELETED ARCHIVED PENDING_REVIEW DISAPPROVED PREAPPROVED PENDING_BILLING_INFO
                    CAMPAIGN_PAUSED ADSET_PAUSED IN_PROCESS WITH_ISSUES].freeze

  def initialize(account:, days: nil, until_date: Date.current)
    @account = account
    @graph = Crm::MetaGraph.new(account: account)
    @until_date = until_date
    @days = days
  end

  def self.state(account)
    (CrmSetting.find_by(account: account)&.meta_ads_config || {})['creatives_sync'] || {}
  end

  def call
    return { configured: false } unless @graph.configured?

    write_state('running_since' => Time.current.iso8601, 'last_error' => nil, 'last_warning' => nil, 'progress' => nil)
    ads = sync_creatives
    rows = load_windows
    recovered = recover_missing_creatives
    write_done_state(ads, rows, recovered)
    Crm::AdCreativeMediaJob.perform_later(@account.id)
    warm_records_cache
    { configured: true, ads: ads, rows: rows, since: since_date, until: @until_date, recovered: recovered, windows: windows.size }
  rescue StandardError => e
    write_state('running_since' => nil, 'last_error' => e.message, 'progress' => nil)
    raise
  end

  # cada janela grava o progresso antes de buscar (a tela mostra "janela 3 de 13")
  def load_windows
    windows.each_with_index.sum do |(w_since, w_until), i|
      write_state('progress' => { 'done' => i, 'total' => windows.size, 'since' => w_since.iso8601, 'until' => w_until.iso8601 })
      sync_insights(w_since, w_until)
    end
  end

  def write_done_state(ads, rows, recovered)
    write_state('running_since' => nil, 'synced_at' => Time.current.iso8601, 'ads' => ads, 'rows' => rows,
                'since' => since_date.iso8601, 'until' => @until_date.iso8601, 'last_error' => nil, 'progress' => nil,
                'recovered' => recovered, 'history_days' => [days, self.class.state(@account)['history_days'].to_i].max)
  end

  def since_date
    @since_date ||= @until_date - (days - 1)
  end

  # janelas de WINDOW_DAYS, da mais recente para a mais antiga (se a carga
  # longa parar no meio, o período recente já está gravado)
  def windows
    @windows ||= begin
      list = []
      w_until = @until_date
      while w_until >= since_date
        w_since = [w_until - (WINDOW_DAYS - 1), since_date].max
        list << [w_since, w_until]
        w_until = w_since - 1
      end
      list
    end
  end

  private

  def days
    @days ||= self.class.state(@account)['synced_at'].present? ? DEFAULT_DAYS : FIRST_SYNC_DAYS
    @days.to_i.clamp(1, MAX_DAYS)
  end

  # ── 1) anúncios + criativos ───────────────────────────────────────────────
  # com todos os status (apagados/arquivados vêm); se a Meta recusar o filtro,
  # refaz sem ele — os apagados ainda voltam pela recuperação por id
  def sync_creatives
    ads = begin
      @graph.fetch_all('ads', { fields: AD_FIELDS, limit: 100, effective_status: ALL_STATUSES.to_json }, max_pages: 20)
    rescue Crm::MetaGraph::Error => e
      Rails.logger.warn "[CEVICO criativos] /ads com filtro de status recusado (#{e.message}); refazendo sem filtro"
      @graph.fetch_all('ads', { fields: AD_FIELDS, limit: 100 }, max_pages: 20)
    end
    now = Time.current
    rows = ads.map { |ad| creative_row(ad, now) }
    upsert_creatives(rows)
    rows.size
  end

  def creative_row(ad_row, now)
    ad = ad_row
    creative = ad['creative'] || {}
    {
      account_id: @account.id, ad_id: ad['id'].to_s, ad_name: ad['name'],
      adset_id: ad.dig('adset', 'id'), adset_name: ad.dig('adset', 'name'),
      campaign_id: ad.dig('campaign', 'id'), campaign_name: ad.dig('campaign', 'name'),
      effective_status: ad['effective_status'], format: Crm::AdCreativeParser.format_for(creative),
      creative: Crm::AdCreativeParser.parse(creative), synced_at: now, created_at: now, updated_at: now
    }
  end

  def upsert_creatives(rows)
    return if rows.empty?

    Crm::AdCreative.upsert_all(rows, unique_by: [:account_id, :ad_id]) # rubocop:disable Rails/SkipsModelValidations
  end

  # ── 2) métricas diárias ───────────────────────────────────────────────────
  # se a Meta recusar algum campo de vídeo, refaz só com o básico (a tela
  # fica sem gancho/retenção até acertarmos o campo, mas não fica sem dados)
  def sync_insights(w_since = since_date, w_until = @until_date)
    raw = begin
      @graph.fetch_all('insights', insights_query(w_since, w_until), max_pages: 60)
    rescue Crm::MetaGraph::Error => e
      Rails.logger.warn "[CEVICO criativos] /insights completo recusado (#{e.message}); refazendo com campos básicos"
      write_state('last_warning' => "Meta recusou as métricas de vídeo: #{e.message}")
      @graph.fetch_all('insights', insights_query(w_since, w_until, BASIC_FIELDS), max_pages: 60)
    end
    now = Time.current
    rows = raw.filter_map { |row| insight_row(row, now) }
    ensure_creatives_for(raw, now)
    rows.each_slice(500) do |slice|
      Crm::AdInsight.upsert_all(slice, unique_by: [:account_id, :ad_id, :date]) # rubocop:disable Rails/SkipsModelValidations
    end
    rows.size
  end

  def insights_query(w_since, w_until, fields = INSIGHT_FIELDS)
    {
      level: 'ad', time_increment: 1, limit: 500,
      fields: fields.join(','),
      time_range: { since: w_since.iso8601, until: w_until.iso8601 }.to_json
    }
  end

  def insight_row(row, now)
    date = Date.parse(row['date_start'].to_s)
    { account_id: @account.id, ad_id: row['ad_id'].to_s, date: date,
      metrics: Crm::AdMetrics.from_meta(row), created_at: now, updated_at: now }
  rescue ArgumentError, TypeError
    nil
  end

  # anúncio com métrica mas fora de /ads (apagado/antigo): cria a linha mínima
  # para a tela não perder o investimento
  def ensure_creatives_for(raw, now)
    known = Crm::AdCreative.where(account_id: @account.id).pluck(:ad_id).to_set
    missing = raw.reject { |r| known.include?(r['ad_id'].to_s) }.uniq { |r| r['ad_id'] }
    rows = missing.map do |r|
      { account_id: @account.id, ad_id: r['ad_id'].to_s, ad_name: r['ad_name'], adset_id: r['adset_id'],
        adset_name: r['adset_name'], campaign_id: r['campaign_id'], campaign_name: r['campaign_name'],
        effective_status: 'UNKNOWN', format: r['video_p25_watched_actions'].present? ? 'video' : 'other',
        creative: {}, synced_at: now, created_at: now, updated_at: now }
    end
    upsert_creatives(rows)
  end

  # ── 3) anúncios apagados: número veio, criativo não → busca por id ───────
  # (a Meta mantém o anúncio legível por id depois de apagado; assim texto,
  # miniatura e status ficam guardados AQUI, e não dependem mais dela)
  def recover_missing_creatives
    missing = Crm::AdCreative.where(account_id: @account.id, effective_status: 'UNKNOWN').where("creative = '{}'::jsonb").pluck(:ad_id)
    return 0 if missing.empty?

    found = @graph.fetch_objects(missing, AD_FIELDS)
    return 0 if found.empty?

    now = Time.current
    rows = found.values.map { |ad| creative_row(ad, now) }
    upsert_creatives(rows)
    rows.size
  end

  # recordes/campeões (cache de 1 h por carga) já prontos quando a tela abrir —
  # com anos de histórico o cálculo leva segundos e não deve cair no clique
  def warm_records_cache
    Crm::CreativeRecords.new(account: @account).call
    Crm::CreativeAnalyticsService.new(account: @account, since_date: @until_date - 29, until_date: @until_date).assets_history(months: 12)
  rescue StandardError => e
    Rails.logger.warn "[CEVICO criativos] cache dos recordes: #{e.message}"
  end

  # ── estado ────────────────────────────────────────────────────────────────
  def write_state(patch)
    settings = CrmSetting.find_by(account: @account)
    return unless settings

    settings.with_lock do
      cfg = settings.meta_ads_config || {}
      cfg['creatives_sync'] = (cfg['creatives_sync'] || {}).merge(patch)
      settings.update_column(:meta_ads_config, cfg) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
