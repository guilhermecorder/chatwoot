# Dashboard GOOGLE (Ads + GA4): mostra as CONVERSÕES que o sistema enviou
# pro Google (via GA4 Measurement Protocol — as ações de coluna
# google_ads_conversion, ex.: consulta realizada, cirurgia realizada) e o
# estado da integração. Investimento/cliques do Google Ads entram quando o
# developer token for conectado (mesmo caminho do painel Meta).
class Api::V1::Accounts::Crm::GoogleDashboardsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:reports) }

  def show
    cfg = CrmSetting.find_by(account: Current.account)&.google_ads_config || {}
    log = cfg['sent_log'] || {}
    render json: {
      configured: cfg['measurement_id'].present? && cfg['api_secret'].present?,
      measurement_id: cfg['measurement_id'],
      ads_token_set: cfg['developer_token'].present?,
      series: series(log),
      totals_by_event: totals_by_event(log),
      automations: conversion_automations
    }
  end

  private


  def series(log)
    (0...30).map do |i|
      date = Date.current - (29 - i)
      day = log[date.iso8601] || {}
      { date: date.iso8601, total: day.values.sum(&:to_i), by_event: day }
    end
  end

  def totals_by_event(log)
    totals = Hash.new(0)
    log.each_value { |day| day.each { |event, n| totals[event] += n.to_i } }
    totals.sort_by { |_e, n| -n }.to_h
  end

  # onde as conversões estão plugadas (ações de coluna google_ads_conversion)
  def conversion_automations
    Crm::Automation.joins(stage: :pipeline)
                   .where(crm_pipelines: { account_id: Current.account.id }, action_type: 'google_ads_conversion')
                   .includes(:stage)
                   .map { |a| { stage: a.stage&.name, event: a.action_config['event_name'] || a.action_config['conversion_name'] } }
  rescue StandardError
    []
  end
end
