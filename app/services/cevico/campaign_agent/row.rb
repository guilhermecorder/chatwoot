# 🧮 UMA LINHA do Agente de Campanhas (item 352): os números da plataforma
# (gasto, exibições, cliques…) + a jornada do CRM (leads, agendou, compareceu,
# fechou, operou, receita) e as TAXAS que saem deles.
#
# Indicadores, nas três camadas que ele pediu:
#   primários    gasto, leads, CPL, agendamentos, custo por agendamento,
#                cirurgias, custo por cirurgia (CAC), receita, ROAS
#   secundários  CTR, CPM, CPC, frequência, conversa por clique, lead por
#                clique, gancho e retenção (vídeo)
#   terciários   taxa de agendamento, comparecimento, fechamento, cirurgia por
#                lead (e, na leitura, o tempo até agendar)
module Cevico::CampaignAgent::Row
  module_function

  PLATFORM_KEYS = %w[spend impressions reach clicks link_clicks conversations plays_3s thruplay].freeze
  FUNNEL_KEYS = %w[leads booked attended closed surgeries revenue].freeze
  SUM_KEYS = (PLATFORM_KEYS + FUNNEL_KEYS).freeze
  GOAL_EVENT = { 'booked' => 'booked', 'surgery' => 'surgeries' }.freeze
  GOAL_COST = { 'booked' => 'cost_booked', 'surgery' => 'cost_surgery' }.freeze
  LOWER_IS_BETTER = %w[cpl cost_booked cost_surgery cpm cpc goal_cost].freeze

  def blank
    SUM_KEYS.index_with { 0.0 }.merge('frequency' => 0.0)
  end

  # soma `other` dentro de `row` (os dois no formato de blank)
  def add!(row, other)
    SUM_KEYS.each { |k| row[k] = row[k].to_f + other[k].to_f }
    row
  end

  # a partir das métricas da Meta já somadas (Crm::AdMetrics.sum) + jornada (Crm::AdFunnel)
  def from_meta(total, funnel)
    row = blank
    PLATFORM_KEYS.each { |k| row[k] = total[k].to_f }
    row['frequency'] = total['frequency'].to_f
    add_funnel!(row, funnel)
  end

  def from_google(spend:, clicks:, impressions:, funnel: nil)
    row = blank.merge('spend' => spend.to_f, 'clicks' => clicks.to_f, 'link_clicks' => clicks.to_f, 'impressions' => impressions.to_f)
    add_funnel!(row, funnel)
  end

  def add_funnel!(row, funnel)
    f = (funnel || {}).to_h.stringify_keys
    FUNNEL_KEYS.each { |k| row[k] = row[k].to_f + f[k].to_f }
    row
  end

  # fecha a linha: inteiros onde cabe, taxas e a estrela-guia (goal)
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def finish(row, goal: 'booked', video: nil)
    spend = row['spend'].to_f.round(2)
    imp = row['impressions'].to_f
    clicks = row['link_clicks'].to_f
    leads = row['leads'].to_f
    booked = row['booked'].to_f
    surgeries = row['surgeries'].to_f
    revenue = row['revenue'].to_f.round(2)
    video = row['plays_3s'].to_f.positive? if video.nil?
    out = row.merge('spend' => spend, 'revenue' => revenue)
    (SUM_KEYS - %w[spend revenue]).each { |k| out[k] = row[k].to_f.round }
    out['frequency'] =
      (if row['frequency'].to_f.positive?
         row['frequency'].to_f
       else
         (row['reach'].to_f.positive? ? imp / row['reach'].to_f : 0)
       end).round(2)
    rates = {
      'cpl' => per(spend, leads), 'cost_booked' => per(spend, booked), 'cost_surgery' => per(spend, surgeries),
      'cost_closed' => per(spend, row['closed']),
      'roas' => spend.positive? && revenue.positive? ? (revenue / spend).round(2) : nil,
      'ctr' => share(clicks, imp), 'cpm' => imp.positive? && spend.positive? ? (spend / imp * 1000).round(2) : nil,
      'cpc' => per(spend, clicks),
      'conv_rate' => share(row['conversations'], clicks), 'lead_rate' => share(leads, clicks),
      'hook_rate' => video ? share(row['plays_3s'], imp) : nil,
      'hold_rate' => video ? share(row['thruplay'], row['plays_3s']) : nil,
      'booking_rate' => share(booked, leads), 'attend_rate' => share(row['attended'], booked),
      'close_rate' => share(row['closed'], row['attended']), 'surgery_rate' => share(surgeries, leads)
    }
    out['rates'] = rates
    out['goal_events'] = row[GOAL_EVENT.fetch(goal, 'booked')].to_f.round
    out['goal_cost'] = rates[GOAL_COST.fetch(goal, 'cost_booked')]
    out
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def per(spend, count)
    count.to_f.positive? && spend.to_f.positive? ? (spend.to_f / count).round(2) : nil
  end

  def share(part, whole)
    whole.to_f.positive? ? (part.to_f / whole).round(4) : nil
  end

  # versão enxuta para guardar na recomendação (antes × depois)
  def snapshot(row)
    keys = %w[spend impressions link_clicks leads booked attended closed surgeries revenue goal_events goal_cost frequency]
    row.slice(*keys).merge('rates' => (row['rates'] || {}).slice('cpl', 'cost_booked', 'cost_surgery', 'ctr', 'cpm', 'cpc', 'booking_rate',
                                                                 'lead_rate'))
  end
end
