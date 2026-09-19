# Quebras de UM anúncio (ou da conta inteira) no período, direto da Meta e
# guardadas em cache por 6 h: posicionamento (Reels/Feed/Stories…), idade ×
# sexo e — no criativo dinâmico — gancho (title_asset), corpo (body_asset) e
# CTA (call_to_action_asset) como ATIVOS separados. Item 172.
class Crm::AdBreakdownService
  KINDS = {
    'summary' => nil, # sem quebra: alcance e frequência REAIS do período (a soma dos dias infla o alcance)
    'placement' => 'publisher_platform,platform_position',
    'age_gender' => 'age,gender',
    'title_asset' => 'title_asset',
    'body_asset' => 'body_asset',
    'call_to_action_asset' => 'call_to_action_asset',
    'video_asset' => 'video_asset',
    'image_asset' => 'image_asset'
  }.freeze
  FULL_FIELDS = %w[spend impressions reach clicks inline_link_clicks actions video_thruplay_watched_actions
                   video_p25_watched_actions video_p50_watched_actions video_p75_watched_actions
                   video_p100_watched_actions].join(',').freeze
  # ativos do criativo dinâmico: a Meta só devolve estas métricas
  ASSET_FIELDS = 'spend,impressions,reach,clicks,actions'.freeze
  CACHE_TTL = 6.hours
  CLOSED_TTL = 30.days

  PLATFORM_LABELS = { 'instagram' => 'Instagram', 'facebook' => 'Facebook', 'audience_network' => 'Audience Network',
                      'messenger' => 'Messenger', 'threads' => 'Threads' }.freeze
  POSITION_LABELS = {
    'feed' => 'Feed', 'instagram_reels' => 'Reels', 'reels' => 'Reels', 'facebook_reels' => 'Reels',
    'instagram_stories' => 'Stories', 'story' => 'Stories', 'facebook_stories' => 'Stories', 'messenger_stories' => 'Stories',
    'video_feeds' => 'Vídeos', 'instagram_explore' => 'Explorar', 'instagram_explore_grid_home' => 'Explorar',
    'instagram_search' => 'Busca', 'search' => 'Busca', 'ig_search' => 'Busca', 'instagram_profile_feed' => 'Perfil',
    'profile_feed' => 'Perfil', 'right_hand_column' => 'Coluna lateral', 'marketplace' => 'Marketplace',
    'classic' => 'Clássico', 'an_classic' => 'Clássico', 'instream_video' => 'In-stream', 'rewarded_video' => 'Vídeo premiado',
    'messenger_inbox' => 'Caixa de entrada', 'biz_disco_feed' => 'Descoberta', 'facebook_groups_feed' => 'Grupos',
    'instagram_reels_overlay' => 'Reels (sobreposição)', 'unknown' => 'Outro'
  }.freeze
  GENDER_LABELS = { 'female' => 'Mulheres', 'male' => 'Homens', 'unknown' => 'Não informado' }.freeze

  def initialize(account:, since_date:, until_date:, kind:, ad_id: nil)
    @account = account
    @since_date = since_date
    @until_date = until_date
    @kind = kind.to_s
    @ad_id = ad_id.presence
    @graph = Crm::MetaGraph.new(account: account)
  end

  def call
    return { rows: [], error: 'quebra desconhecida' } unless KINDS.key?(@kind)
    return { rows: [], configured: false } unless @graph.configured?

    Rails.cache.fetch(cache_key, expires_in: ttl) { { rows: fetch_rows, cached_at: Time.current.iso8601 } }
  rescue StandardError => e
    Rails.logger.error "[CEVICO criativos] quebra #{@kind} conta #{@account.id}: #{e.message}"
    { rows: [], error: e.message }
  end

  private

  def asset?
    @kind.end_with?('_asset')
  end

  # período fechado (a Meta só reprocessa os últimos 3 dias) fica 30 dias em
  # cache: as quebras mês a mês do histórico não voltam a bater na Meta
  def ttl
    @until_date < Date.current - 3 ? CLOSED_TTL : CACHE_TTL
  end

  def cache_key
    "crm:ad_breakdown:#{@account.id}:#{@kind}:#{@ad_id || 'all'}:#{@since_date.iso8601}:#{@until_date.iso8601}"
  end

  def fetch_rows
    query = { level: 'ad', limit: 500, fields: asset? ? ASSET_FIELDS : "#{FULL_FIELDS},frequency",
              time_range: { since: @since_date.iso8601, until: @until_date.iso8601 }.to_json }
    query[:breakdowns] = KINDS[@kind] if KINDS[@kind]
    query[:filtering] = [{ field: 'ad.id', operator: 'EQUAL', value: @ad_id }].to_json if @ad_id
    raw = @graph.fetch_all('insights', query, max_pages: 10)
    build_rows(raw)
  end

  def build_rows(raw)
    grouped = raw.group_by { |r| segment_key(r) }
    total_impressions = raw.sum { |r| r['impressions'].to_i }.to_f
    rows = grouped.map do |key, list|
      total = Crm::AdMetrics.sum(list.map { |r| Crm::AdMetrics.from_meta(r) })
      row_for(key, list.first, total, total_impressions)
    end
    rows.sort_by { |r| -r[:impressions] }
  end

  # rubocop:disable Metrics/AbcSize
  def row_for(key, sample, total, total_impressions)
    video = total['thruplay'].to_f.positive? || total['plays_3s'].to_f.positive?
    rates = Crm::AdMetrics.rates(total, video: video)
    ctr_basis = total['link_clicks'].to_f.positive? ? total['link_clicks'].to_f : total['clicks'].to_f
    {
      key: key, label: label_for(sample), meta: meta_for(sample),
      spend: total['spend'].to_f.round(2), impressions: total['impressions'].to_i, reach: total['reach'].to_i,
      clicks: total['clicks'].to_i, link_clicks: total['link_clicks'].to_i, conversations: total['conversations'].to_i,
      plays_3s: total['plays_3s'].to_i, thruplay: total['thruplay'].to_i,
      share: total_impressions.positive? ? (total['impressions'].to_f / total_impressions).round(4) : 0,
      hook_rate: rates['hook_rate'], hold_rate: rates['hold_rate'],
      link_ctr: total['impressions'].to_f.positive? ? (ctr_basis / total['impressions'].to_f) : nil,
      conv_rate: ctr_basis.positive? ? (total['conversations'].to_f / ctr_basis) : nil,
      cost_conversation: rates['cost_conversation'], cpm: rates['cpm'],
      frequency: @kind == 'summary' ? sample['frequency'].to_f.round(2) : nil
    }.compact
  end
  # rubocop:enable Metrics/AbcSize

  def segment_key(row)
    case @kind
    when 'summary' then 'periodo'
    when 'placement' then "#{row['publisher_platform']}|#{row['platform_position']}"
    when 'age_gender' then "#{row['age']}|#{row['gender']}"
    else (row[@kind].is_a?(Hash) ? row[@kind]['id'] : row[@kind]).to_s
    end
  end

  def label_for(row) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    case @kind
    when 'summary' then 'Período'
    when 'placement'
      "#{PLATFORM_LABELS[row['publisher_platform']] || row['publisher_platform'].to_s.humanize} · " \
      "#{POSITION_LABELS[row['platform_position']] || row['platform_position'].to_s.humanize}"
    when 'age_gender' then "#{row['age']} · #{GENDER_LABELS[row['gender']] || row['gender']}"
    when 'call_to_action_asset' then Crm::AdCreativeParser.cta_label(row.dig(@kind, 'name'))
    when 'video_asset' then row.dig(@kind, 'video_name').presence || "Vídeo #{row.dig(@kind, 'video_id')}"
    when 'image_asset' then row.dig(@kind, 'name').presence || "Imagem #{row.dig(@kind, 'hash')}"
    else row.dig(@kind, 'text').to_s
    end
  end

  def meta_for(row)
    return {} unless row[@kind].is_a?(Hash)

    row[@kind].slice('id', 'text', 'name', 'url', 'thumbnail_url', 'video_id', 'hash')
  end
end
