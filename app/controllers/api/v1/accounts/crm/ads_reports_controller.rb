# Relatório "qual anúncio gerou venda": junta as métricas por anúncio da
# Marketing API (investimento/impressões/cliques) com a atribuição CTWA
# gravada nos contatos (leads) e as conversões do CRM (cards que chegaram
# na etapa de conversão, ex. Cirurgia).
class Api::V1::Accounts::Crm::AdsReportsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:reports) }

  # GET /api/v1/accounts/:account_id/crm/ads_report?since=YYYY-MM-DD&until=YYYY-MM-DD
  def show
    meta = Crm::MetaAdsReportService.new(
      account: Current.account,
      since_date: since_date,
      until_date: until_date
    ).call

    render json: {
      configured: meta[:configured],
      error: meta[:error],
      since: since_date,
      until: until_date,
      conversion_stage_ids: conversion_stage_ids,
      stages: stages_json,
      needs_backfill: needs_backfill?,
      rows: build_rows(meta[:rows]),
      unattributed_leads: unattributed_leads_count
    }
  end

  # POST /api/v1/accounts/:account_id/crm/ads_report/backfill
  # Processa mensagens antigas com referral e carimba a atribuição.
  def backfill
    count = Crm::AdAttributionBackfillJob.referral_messages(Current.account).count
    Crm::AdAttributionBackfillJob.perform_later(Current.account.id)
    render json: { enqueued: true, messages: count }
  end

  private


  def since_date
    @since_date ||= begin
      Date.parse(params[:since])
    rescue StandardError
      30.days.ago.to_date
    end
  end

  def until_date
    @until_date ||= begin
      Date.parse(params[:until])
    rescue StandardError
      Date.current
    end
  end

  # ── Lado local: leads atribuídos e conversões ─────────────────────────────

  # [contact_id, source_id, headline, source_url] dos contatos que chegaram
  # por anúncio dentro do período
  def attributed_contacts
    @attributed_contacts ||= Current.account.contacts
                                    .where("additional_attributes -> 'meta_ads' ->> 'source_id' IS NOT NULL")
                                    .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz >= ?",
                                           since_date.beginning_of_day)
                                    .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz <= ?",
                                           until_date.end_of_day)
                                    .pluck(:id,
                                           Arel.sql("additional_attributes -> 'meta_ads' ->> 'source_id'"),
                                           Arel.sql("additional_attributes -> 'meta_ads' ->> 'headline'"),
                                           Arel.sql("additional_attributes -> 'meta_ads' ->> 'source_url'"))
  end

  # contatos com atribuição registrada (qualquer anúncio), fora do recorte:
  # ajuda a mostrar quanto do movimento veio sem anúncio no período
  def unattributed_leads_count
    total = Current.account.contacts
                   .where(created_at: since_date.beginning_of_day..until_date.end_of_day)
                   .count
    [total - attributed_contacts.size, 0].max
  end

  def conversion_stage_ids
    @conversion_stage_ids ||= begin
      configured = Array(meta_config['conversion_stage_ids']).map(&:to_i).reject(&:zero?)
      if configured.any?
        configured
      else
        # padrão: etapas com "cirurgia" no nome (conversão principal da clínica)
        Crm::Stage.joins(:pipeline)
                  .where(crm_pipelines: { account_id: Current.account.id })
                  .where('crm_stages.name ILIKE ?', '%cirurgia%')
                  .pluck(:id)
      end
    end
  end

  def stages_json
    Crm::Stage.joins(:pipeline)
              .where(crm_pipelines: { account_id: Current.account.id })
              .order('crm_pipelines.position, crm_stages.position')
              .pluck(:id, :name)
              .map { |id, name| { id: id, name: name } }
  end

  # contact_id → valor do card, só para quem converteu (entrou na etapa de
  # conversão em algum momento — stage_logs — ou está nela agora)
  def converted_values_by_contact
    @converted_values_by_contact ||= begin
      contact_ids = attributed_contacts.map(&:first)
      return {} if contact_ids.empty? || conversion_stage_ids.empty?

      cards = Crm::Contact.joins(:pipeline)
                          .where(crm_pipelines: { account_id: Current.account.id })
                          .where(contact_id: contact_ids)

      converted_card_ids = cards.where(stage_id: conversion_stage_ids).pluck(:id) |
                           Crm::StageLog.where(crm_contact_id: cards.select(:id), stage_id: conversion_stage_ids)
                                        .pluck(:crm_contact_id)

      cards.where(id: converted_card_ids).pluck(:contact_id, :value).to_h
    end
  end

  # ── Junção Meta × local ────────────────────────────────────────────────────

  def build_rows(meta_rows)
    local = Hash.new { |h, k| h[k] = { leads: 0, conversions: 0, revenue: 0.0, headline: nil, source_url: nil } }

    attributed_contacts.each do |contact_id, source_id, headline, source_url|
      entry = local[source_id]
      entry[:leads] += 1
      entry[:headline] ||= headline
      entry[:source_url] ||= source_url
      if converted_values_by_contact.key?(contact_id)
        entry[:conversions] += 1
        entry[:revenue] += converted_values_by_contact[contact_id].to_f
      end
    end

    rows = meta_rows.map do |meta_row|
      stats = local.delete(meta_row[:ad_id]) || { leads: 0, conversions: 0, revenue: 0.0 }
      compose_row(meta_row, stats)
    end

    # anúncios que trouxeram leads mas não apareceram nos insights do período
    # (anúncio pausado/antigo — o lead ainda conta)
    local.each do |source_id, stats|
      rows << compose_row(
        { ad_id: source_id, ad_name: stats[:headline].presence || "Anúncio #{source_id}",
          adset_name: nil, campaign_name: nil, spend: 0.0, impressions: 0, reach: 0, link_clicks: 0 },
        stats.merge(source_url: stats[:source_url])
      )
    end

    rows.sort_by { |r| [-r[:conversions], -r[:leads], -r[:spend]] }
  end

  def compose_row(meta_row, stats)
    spend = meta_row[:spend].to_f
    leads = stats[:leads]
    conversions = stats[:conversions]
    revenue = stats[:revenue].to_f

    meta_row.merge(
      source_url: stats[:source_url],
      leads: leads,
      conversions: conversions,
      revenue: revenue.round(2),
      cpl: leads.positive? && spend.positive? ? (spend / leads).round(2) : nil,
      cac: conversions.positive? && spend.positive? ? (spend / conversions).round(2) : nil,
      roas: spend.positive? && revenue.positive? ? (revenue / spend).round(2) : nil
    )
  end

  # existe mensagem antiga com referral cujo contato ainda não foi carimbado?
  def needs_backfill?
    attributed = Current.account.contacts
                        .where("additional_attributes -> 'meta_ads' IS NOT NULL")
                        .select(:id)
    Crm::AdAttributionBackfillJob.referral_messages(Current.account)
                                 .where.not(sender_id: attributed)
                                 .exists?
  rescue StandardError
    false
  end

  def meta_config
    @meta_config ||= CrmSetting.find_by(account: Current.account)&.meta_ads_config || {}
  end
end
