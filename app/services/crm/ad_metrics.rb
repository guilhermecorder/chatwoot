# Normaliza UMA linha de insights da Meta (nível anúncio) para o hash que fica
# em cevico_ad_insights.metrics, e calcula as TAXAS que traduzem gancho, corpo
# e CTA em número:
#   gancho  → taxa de parada  = plays de 3 s ÷ impressões (só vídeo)
#   corpo   → retenção        = ThruPlay ÷ plays de 3 s (+ curva 25/50/75/100 %)
#   CTA     → ação            = cliques no link ÷ impressões, conversas ÷ cliques
module Crm::AdMetrics
  module_function

  CONVERSATION = 'onsite_conversion.messaging_conversation_started_7d'.freeze
  FIRST_REPLY = 'onsite_conversion.messaging_first_reply'.freeze
  SUM_KEYS = %w[spend impressions reach clicks link_clicks plays_3s plays_2s thruplay p25 p50 p75 p100
                conversations first_replies leads post_engagement].freeze

  # rubocop:disable Metrics/AbcSize
  def from_meta(row)
    actions = action_hash(row['actions'])
    {
      'spend' => row['spend'].to_f.round(2), 'impressions' => row['impressions'].to_i, 'reach' => row['reach'].to_i,
      'frequency' => row['frequency'].to_f.round(2), 'clicks' => row['clicks'].to_i,
      'link_clicks' => row['inline_link_clicks'].to_i,
      'plays_3s' => actions['video_view'].to_i,
      'plays_2s' => sum_values(row['video_continuous_2_sec_watched_actions']),
      'thruplay' => sum_values(row['video_thruplay_watched_actions']),
      'p25' => sum_values(row['video_p25_watched_actions']), 'p50' => sum_values(row['video_p50_watched_actions']),
      'p75' => sum_values(row['video_p75_watched_actions']), 'p100' => sum_values(row['video_p100_watched_actions']),
      'avg_watch' => first_value(row['video_avg_time_watched_actions']).to_f.round(1),
      'conversations' => actions[CONVERSATION].to_i, 'first_replies' => actions[FIRST_REPLY].to_i,
      'leads' => (actions['lead'].presence || actions['onsite_conversion.lead_grouped']).to_i,
      'post_engagement' => actions['post_engagement'].to_i,
      'actions' => actions
    }
  end
  # rubocop:enable Metrics/AbcSize

  def action_hash(list)
    Array(list).each_with_object({}) { |a, h| h[a['action_type'].to_s] = a['value'] if a.is_a?(Hash) }
  end

  def sum_values(list)
    Array(list).sum { |a| a.is_a?(Hash) ? a['value'].to_f : 0 }.round
  end

  def first_value(list)
    Array(list).first.is_a?(Hash) ? Array(list).first['value'] : nil
  end

  # Soma vários dias (ou vários segmentos) num só hash
  def sum(metrics_list) # rubocop:disable Metrics/AbcSize
    total = Hash.new(0)
    watch = []
    metrics_list.each do |m|
      SUM_KEYS.each { |k| total[k] += m[k].to_f }
      watch << [m['avg_watch'].to_f, m['plays_3s'].to_f] if m['avg_watch'].to_f.positive?
    end
    total['spend'] = total['spend'].round(2)
    total['avg_watch'] = weighted_avg(watch)
    total['frequency'] = total['reach'].positive? ? (total['impressions'] / total['reach']).round(2) : 0
    total
  end

  def weighted_avg(pairs)
    weight = pairs.sum { |_v, w| w }
    return 0 if weight.zero?

    (pairs.sum { |v, w| v * w } / weight).round(1)
  end

  # Taxas a partir de um total (vídeo devolve gancho/retenção; imagem só ação)
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def rates(total, video: true)
    impressions = total['impressions'].to_f
    plays = total['plays_3s'].to_f
    clicks = total['link_clicks'].to_f
    conversations = total['conversations'].to_f
    spend = total['spend'].to_f
    {
      'hook_rate' => video && impressions.positive? ? (plays / impressions) : nil,
      'hold_rate' => video && plays.positive? ? (total['thruplay'].to_f / plays) : nil,
      'retention' => video && impressions.positive? ? retention_curve(total) : nil,
      'avg_watch' => video ? total['avg_watch'].to_f : nil,
      'link_ctr' => impressions.positive? ? (clicks / impressions) : nil,
      'conv_rate' => clicks.positive? ? (conversations / clicks) : nil,
      'cost_conversation' => conversations.positive? ? (spend / conversations).round(2) : nil,
      'cpm' => impressions.positive? ? (spend / impressions * 1000).round(2) : nil,
      'cpc' => clicks.positive? ? (spend / clicks).round(2) : nil,
      'frequency' => total['frequency'].to_f
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # % das impressões que chegou a cada marco: 3 s → 25 → 50 → 75 → 100 %
  def retention_curve(total)
    impressions = total['impressions'].to_f
    %w[plays_3s p25 p50 p75 p100].map { |k| (total[k].to_f / impressions).clamp(0, 1).round(4) }
  end
end
