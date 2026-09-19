# Dados FICTÍCIOS no formato exato da Marketing API (ads, insights diários e
# breakdowns) para testar a Central de Criativos sem conta da Meta.
# Só entra com CEVICO_META_SIMULATE=1. Determinístico (mesmos números sempre).
class Crm::MetaSimulator
  ADS = [
    { id: '2301', name: 'VID · Catarata · Gancho "Enxergar sem óculos"', format: 'video', hook: 0.42, hold: 0.36, ctr: 0.021, conv: 0.55, cpm: 24.0,
      status: 'ACTIVE' },
    { id: '2302', name: 'VID · Catarata · Gancho "Sua visão embaçou?"', format: 'video', hook: 0.31, hold: 0.18, ctr: 0.013, conv: 0.40, cpm: 22.0,
      status: 'ACTIVE' },
    { id: '2303', name: 'VID · Refrativa · Depoimento Ana', format: 'video', hook: 0.27, hold: 0.44, ctr: 0.017, conv: 0.62, cpm: 27.0,
      status: 'ACTIVE' },
    { id: '2304', name: 'VID · Refrativa · Gancho "Cansou das lentes?"', format: 'video', hook: 0.46, hold: 0.22, ctr: 0.009, conv: 0.30, cpm: 21.0,
      status: 'ACTIVE', fatigue: true },
    { id: '2305', name: 'IMG · Catarata · Trifocal · Prova social', format: 'image', ctr: 0.015, conv: 0.48, cpm: 19.0, status: 'ACTIVE' },
    { id: '2306', name: 'IMG · Refrativa · Oferta avaliação', format: 'image', ctr: 0.006, conv: 0.25, cpm: 17.0, status: 'PAUSED' },
    { id: '2307', name: 'DIN · Catarata · 3 ganchos × 2 CTAs', format: 'dynamic', hook: 0.35, hold: 0.30, ctr: 0.018, conv: 0.50, cpm: 23.0,
      status: 'ACTIVE' },
    { id: '2308', name: 'CAR · Lentes premium · 5 cards', format: 'carousel', ctr: 0.011, conv: 0.35, cpm: 20.0, status: 'ACTIVE' }
  ].freeze
  # anúncio APAGADO na Meta: some de /ads, mas tem números antigos (mais de
  # 45 dias) e continua legível por id — testa a recuperação do histórico
  DELETED_ADS = [
    { id: '2309', name: 'VID · Catarata · Antigo · Gancho "Nova visão"', format: 'video', hook: 0.33, hold: 0.28, ctr: 0.012, conv: 0.45,
      cpm: 20.0, status: 'DELETED', min_age: 46 }
  ].freeze
  ALL_ADS = (ADS + DELETED_ADS).freeze

  TITLES = ['Enxergar sem óculos é possível', 'Sua visão embaçou?', 'Cansou das lentes?'].freeze
  BODIES = [
    "A catarata não espera.\nA CEVICO avalia em 1 consulta.\nAgende pelo WhatsApp.",
    "Lente trifocal: longe, perto e meio.\nTecnologia de ponta com acolhimento.\nFale com a gente."
  ].freeze
  CTAS = %w[WHATSAPP_MESSAGE LEARN_MORE].freeze
  PLACEMENTS = [%w[instagram reels], %w[instagram feed], %w[instagram story], %w[facebook feed], %w[facebook video_feeds],
                %w[audience_network classic]].freeze
  AGES = %w[25-34 35-44 45-54 55-64 65+].freeze

  def initialize(account:)
    @account = account
  end

  def fetch_all(edge, query)
    return ads_rows if edge == 'ads'

    breakdowns = query[:breakdowns].to_s
    return daily_rows(query) if breakdowns.blank?

    breakdown_rows(query, breakdowns)
  end

  def fetch_objects(ids, _fields)
    wanted = Array(ids).map(&:to_s)
    ALL_ADS.select { |ad| wanted.include?(ad[:id]) }.to_h { |ad| [ad[:id], ad_object(ad)] }
  end

  private

  def ads_rows
    ADS.map { |ad| ad_object(ad) }
  end

  def ad_object(spec)
    ad = spec
    {
      'id' => ad[:id], 'name' => ad[:name], 'effective_status' => ad[:status],
      'adset' => { 'id' => "1#{ad[:id]}", 'name' => "Conjunto #{ad[:name].split(' · ')[1]}" },
      'campaign' => { 'id' => campaign_id(ad), 'name' => "Campanha #{ad[:name].split(' · ')[1]} · CTWA" },
      'creative' => creative_for(ad)
    }
  end

  def campaign_id(spec)
    spec[:name].include?('Catarata') ? '9001' : '9002'
  end

  def creative_for(spec) # rubocop:disable Metrics/AbcSize
    ad = spec
    base = { 'id' => "c#{ad[:id]}", 'name' => ad[:name], 'call_to_action_type' => CTAS[ad[:id].to_i % 2],
             'thumbnail_url' => "https://picsum.photos/seed/#{ad[:id]}/320/400" }
    case ad[:format]
    when 'video'
      base.merge('object_story_spec' => { 'video_data' => { 'video_id' => "v#{ad[:id]}", 'title' => ad[:name][/"(.+)"/, 1] || TITLES[0],
                                                            'message' => BODIES[ad[:id].to_i % 2], 'image_url' => base['thumbnail_url'],
                                                            'call_to_action' => { 'type' => base['call_to_action_type'] } } })
    when 'image'
      base.merge('title' => TITLES[ad[:id].to_i % 3], 'body' => BODIES[ad[:id].to_i % 2], 'image_url' => base['thumbnail_url'])
    when 'dynamic'
      base.merge('asset_feed_spec' => { 'titles' => TITLES.map { |t| { 'text' => t } }, 'bodies' => BODIES.map { |b| { 'text' => b } },
                                        'call_to_action_types' => CTAS, 'videos' => [{ 'video_id' => "v#{ad[:id]}" }] })
    else
      base.merge('object_story_spec' => { 'link_data' => { 'name' => TITLES[0], 'message' => BODIES[0], 'picture' => base['thumbnail_url'],
                                                           'child_attachments' => Array.new(5) { { 'name' => 'card' } } } })
    end
  end

  def range(query)
    tr = JSON.parse(query[:time_range].to_s) rescue {} # rubocop:disable Style/RescueModifier
    since = Date.parse(tr['since'].to_s) rescue Date.current - 29 # rubocop:disable Style/RescueModifier
    until_d = Date.parse(tr['until'].to_s) rescue Date.current # rubocop:disable Style/RescueModifier
    [since, until_d]
  end

  def daily_rows(query)
    since, until_d = range(query)
    ALL_ADS.flat_map do |ad|
      (since..until_d).filter_map do |day|
        next if ad[:min_age] && (Date.current - day).to_i < ad[:min_age]

        insight_row(ad, day, 1.0, day.iso8601)
      end
    end
  end

  def breakdown_rows(query, breakdowns)
    since, until_d = range(query)
    days = (until_d - since).to_i + 1
    ads = filtered_ads(query)
    ads.flat_map do |ad|
      segments_for(breakdowns, ad).map do |seg, share|
        insight_row(ad, since, days * share, nil).merge(seg)
      end
    end
  end

  def filtered_ads(query)
    filter = JSON.parse(query[:filtering].to_s) rescue [] # rubocop:disable Style/RescueModifier
    wanted = filter.find { |f| f['field'] == 'ad.id' }&.dig('value')
    wanted.present? ? ALL_ADS.select { |ad| ad[:id] == wanted.to_s } : ADS
  end

  SHARES = { placement: [0.34, 0.22, 0.14, 0.18, 0.08, 0.04].freeze, title: [0.5, 0.3, 0.2].freeze,
             body: [0.6, 0.4].freeze, cta: [0.65, 0.35].freeze }.freeze

  def segments_for(breakdowns, spec) # rubocop:disable Metrics/CyclomaticComplexity
    ad = spec
    case breakdowns
    when 'publisher_platform,platform_position'
      PLACEMENTS.each_with_index.map { |(pl, pos), i| [{ 'publisher_platform' => pl, 'platform_position' => pos }, SHARES[:placement][i]] }
    when 'age,gender'
      AGES.flat_map { |age| [[{ 'age' => age, 'gender' => 'female' }, 0.12], [{ 'age' => age, 'gender' => 'male' }, 0.08]] }
    when 'title_asset'
      TITLES.each_with_index.map { |t, i| [{ 'title_asset' => { 'text' => t, 'id' => "t#{i}" } }, SHARES[:title][i]] }
    when 'body_asset'
      BODIES.each_with_index.map { |b, i| [{ 'body_asset' => { 'text' => b, 'id' => "b#{i}" } }, SHARES[:body][i]] }
    when 'call_to_action_asset'
      CTAS.each_with_index.map { |c, i| [{ 'call_to_action_asset' => { 'name' => c, 'id' => "cta#{i}" } }, SHARES[:cta][i]] }
    else
      [[{ breakdowns => { 'id' => "x#{ad[:id]}", 'name' => ad[:name] } }, 1.0]]
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
  def insight_row(spec, day, scale, date_str)
    ad = spec
    seed = ((ad[:id].to_i * 31) + day.yday) % 17
    wave = 1.0 + ((seed - 8) / 40.0)
    fatigue = ad[:fatigue] ? [0.35, 1.0 - ((Date.current - day).to_i.clamp(0, 60) * -0.012)].max : 1.0
    ctr_mult = ad[:fatigue] ? (1.4 - (0.02 * (60 - (Date.current - day).to_i.clamp(0, 60)))) : 1.0
    impressions = (1800 * wave * scale * fatigue).round
    reach = (impressions * 0.72).round
    spend = (impressions / 1000.0 * ad[:cpm] * wave).round(2)
    plays3 = ad[:hook] ? (impressions * ad[:hook] * wave).round : 0
    thru = ad[:hold] ? (plays3 * ad[:hold]).round : 0
    link_clicks = (impressions * ad[:ctr] * ctr_mult * wave).round
    conversations = (link_clicks * ad[:conv]).round
    row = {
      'ad_id' => ad[:id], 'ad_name' => ad[:name],
      'adset_id' => "1#{ad[:id]}", 'adset_name' => "Conjunto #{ad[:name].split(' · ')[1]}",
      'campaign_id' => campaign_id(ad), 'campaign_name' => "Campanha #{ad[:name].split(' · ')[1]} · CTWA",
      'spend' => spend.to_s, 'impressions' => impressions.to_s, 'reach' => reach.to_s,
      'frequency' => (impressions / [reach, 1].max.to_f).round(2).to_s,
      'clicks' => (link_clicks * 1.6).round.to_s, 'inline_link_clicks' => link_clicks.to_s,
      'actions' => [
        { 'action_type' => 'video_view', 'value' => plays3.to_s },
        { 'action_type' => 'link_click', 'value' => link_clicks.to_s },
        { 'action_type' => 'onsite_conversion.messaging_conversation_started_7d', 'value' => conversations.to_s },
        { 'action_type' => 'onsite_conversion.messaging_first_reply', 'value' => (conversations * 0.8).round.to_s },
        { 'action_type' => 'post_engagement', 'value' => (impressions * 0.05).round.to_s }
      ],
      'cost_per_action_type' => [{ 'action_type' => 'onsite_conversion.messaging_conversation_started_7d',
                                   'value' => (conversations.positive? ? spend / conversations : 0).round(2).to_s }]
    }
    row['date_start'] = row['date_stop'] = date_str if date_str
    return row unless ad[:hook]

    row.merge(
      'video_play_actions' => [{ 'action_type' => 'video_view', 'value' => (impressions * 0.9).round.to_s }],
      'video_continuous_2_sec_watched_actions' => [{ 'action_type' => 'video_view', 'value' => (plays3 * 1.3).round.to_s }],
      'video_thruplay_watched_actions' => [{ 'action_type' => 'video_view', 'value' => thru.to_s }],
      'video_p25_watched_actions' => [{ 'action_type' => 'video_view', 'value' => (plays3 * 0.78).round.to_s }],
      'video_p50_watched_actions' => [{ 'action_type' => 'video_view', 'value' => (plays3 * 0.52).round.to_s }],
      'video_p75_watched_actions' => [{ 'action_type' => 'video_view', 'value' => (plays3 * 0.31).round.to_s }],
      'video_p100_watched_actions' => [{ 'action_type' => 'video_view', 'value' => (plays3 * 0.19).round.to_s }],
      'video_avg_time_watched_actions' => [{ 'action_type' => 'video_view', 'value' => (6 + (ad[:hold] * 20)).round(1).to_s }]
    )
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
end
