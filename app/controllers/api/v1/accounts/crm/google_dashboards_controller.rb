# Dashboard GOOGLE (Ads + GA4) — 06/08, repaginado:
#  • conversões que o sistema ENVIA pro Google (sent_log do Measurement
#    Protocol), agora respeitando a régua de período padrão;
#  • PALAVRAS-CHAVE / termos de pesquisa / campanhas com cliques e custo,
#    lidos da API de dados do GA4 (conta de serviço — sem developer token);
#  • funil DO TERMO À CIRURGIA cruzando o carimbo page_ads dos leads
#    (utm_term/gclid capturados nas páginas) com consultas e cirurgias.
class Api::V1::Accounts::Crm::GoogleDashboardsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  before_action -> { require_capability(:reports) }

  def show
    cfg = CrmSetting.find_by(account: Current.account)&.google_ads_config || {}
    log = cfg['sent_log'] || {}
    since, until_at = standard_period_range || default_range

    render json: {
      configured: cfg['measurement_id'].present? && cfg['api_secret'].present?,
      measurement_id: cfg['measurement_id'],
      ads_token_set: cfg['developer_token'].present?,
      insights_configured: cfg['ga4_property_id'].present? && cfg['service_account_json'].present?,
      period: { from: since.to_date.iso8601, to: until_at.to_date.iso8601 },
      series: series(log, since, until_at),
      totals_by_event: totals_by_event(log, since, until_at),
      automations: conversion_automations,
      google_data: google_data(since, until_at),
      keyword_funnel: keyword_funnel(since, until_at)
    }
  end

  private

  def default_range
    now = PERIOD_TZ.now
    [now.beginning_of_month, now.end_of_day]
  end

  # série diária das conversões enviadas dentro do período (o sent_log
  # guarda ~90 dias — períodos maiores mostram os últimos 90 do intervalo)
  def series(log, since, until_at)
    first = since.to_date
    last = until_at.to_date
    first = last - 89 if (last - first).to_i > 89

    (first..last).map do |date|
      day = log[date.iso8601] || {}
      { date: date.iso8601, total: day.values.sum(&:to_i), by_event: day }
    end
  end

  def totals_by_event(log, since, until_at)
    range = (since.to_date.iso8601)..(until_at.to_date.iso8601)
    totals = Hash.new(0)
    log.each do |date, day|
      next unless range.cover?(date)

      day.each { |event, n| totals[event] += n.to_i }
    end
    totals.sort_by { |_e, n| -n }.to_h
  end

  # GA4 Data API (keywords/queries/campanhas) — 3 chamadas HTTP, cache 10min
  def google_data(since, until_at)
    Rails.cache.fetch(
      "cevico:google_keywords:#{Current.account.id}:#{since.to_date}:#{until_at.to_date}",
      expires_in: 10.minutes
    ) do
      Crm::GoogleKeywordsService.new(
        account: Current.account,
        since_date: since.to_date,
        until_date: until_at.to_date
      ).call
    end
  end

  # ── Do termo à cirurgia (dados do BANCO, via carimbo page_ads) ────────
  # Leads do Google capturados no período, agrupados pelo utm_term (cai para
  # a campanha quando o anúncio não manda {keyword}), com a jornada de cada
  # grupo: agendou consulta → compareceu → fechou cirurgia (+ receita).
  def keyword_funnel(since, until_at)
    leads = Current.account.contacts
                   .where("additional_attributes -> 'page_ads' ->> 'source' = 'google_ads'")
                   .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz >= ?", since)
                   .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz <= ?", until_at)
                   .pluck(:id,
                          Arel.sql("additional_attributes -> 'page_ads' ->> 'utm_term'"),
                          Arel.sql("additional_attributes -> 'page_ads' ->> 'campaign'"))
    return { total_leads: 0, with_term: 0, rows: [] } if leads.empty?

    ids = leads.map(&:first)
    booked = Current.account.tasks.where(task_type: 'consulta', contact_id: ids)
                    .distinct.pluck(:contact_id).to_set
    attended = Current.account.tasks.where(task_type: 'consulta', attendance: 'attended', contact_id: ids)
                      .distinct.pluck(:contact_id).to_set
    converted = converted_values(ids)

    rows = Hash.new { |h, k| h[k] = { leads: 0, booked: 0, attended: 0, surgeries: 0, revenue: 0.0 } }
    with_term = 0
    leads.each do |id, term, campaign|
      with_term += 1 if term.present?
      key = term.presence || (campaign.presence && "campanha: #{campaign}") || '(sem termo)'
      row = rows[key]
      row[:leads] += 1
      row[:booked] += 1 if booked.include?(id)
      row[:attended] += 1 if attended.include?(id)
      if converted.key?(id)
        row[:surgeries] += 1
        row[:revenue] += converted[id].to_f
      end
    end

    {
      total_leads: ids.size,
      with_term: with_term,
      rows: rows.map { |term, r| { term: term }.merge(r.merge(revenue: r[:revenue].round(2))) }
                .sort_by { |r| [-r[:leads], -r[:surgeries]] }
                .first(50)
    }
  end

  # mesma régua do relatório de Páginas: etapas com "cirurgia" no nome
  # (sem as de indicação) — chegou lá = fechou
  def surgery_stage_ids
    @surgery_stage_ids ||= begin
      base = Crm::Stage.joins(:pipeline)
                       .where(crm_pipelines: { account_id: Current.account.id })
                       .where('crm_stages.name ILIKE ?', '%cirurgia%')
      strict = base.where.not('crm_stages.name ILIKE ?', '%indica%').pluck(:id)
      strict.any? ? strict : base.pluck(:id)
    end
  end

  # contact_id → valor do card, só de quem chegou numa etapa de cirurgia
  def converted_values(contact_ids)
    return {} if contact_ids.empty? || surgery_stage_ids.empty?

    cards = Crm::Contact.joins(:pipeline)
                        .where(crm_pipelines: { account_id: Current.account.id })
                        .where(contact_id: contact_ids)
    converted_ids = cards.where(stage_id: surgery_stage_ids).pluck(:id) |
                    Crm::StageLog.where(crm_contact_id: cards.select(:id), stage_id: surgery_stage_ids)
                                 .pluck(:crm_contact_id)
    cards.where(id: converted_ids).pluck(:contact_id, :value).to_h
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
