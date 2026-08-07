# Aba RESULTADOS do ambiente de Páginas (plano 100+ páginas com ads):
# por página e por origem (Google Ads, Google orgânico/SEO, Meta, funil,
# direto) — visitas, cliques no WhatsApp, leads que chegaram na caixa com
# Protocolo, quantos agendaram consulta e quantos fecharam cirurgia (com
# receita). O lado "quanto custou" continua no relatório de Anúncios;
# aqui a pergunta é "qual PÁGINA e qual ORIGEM trazem paciente de verdade".
class Api::V1::Accounts::Crm::PagesReportsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod
  before_action -> { require_capability(:pages) }

  # GET /api/v1/accounts/:id/crm/pages_report?preset=month (régua padrão)
  # ou ?since=YYYY-MM-DD&until=YYYY-MM-DD (legado)
  def show
    render json: {
      since: since_date,
      until: until_date,
      sources: Cevico::TrafficSource::SOURCES,
      rows: rows_json,
      protocol: protocol_json
    }
  end

  private

  # régua padrão CEVICO (06/08) via concern; since/until soltos = legado
  def standard_range
    @standard_range ||= standard_period_range
  end

  def since_date
    @since_date ||= if standard_range
                      standard_range.first.to_date
                    else
                      begin
                        Date.parse(params[:since])
                      rescue StandardError
                        30.days.ago.to_date
                      end
                    end
  end

  def until_date
    @until_date ||= if standard_range
                      standard_range.last.to_date
                    else
                      begin
                        Date.parse(params[:until])
                      rescue StandardError
                        Date.current
                      end
                    end
  end

  # ── tráfego agregado (visitas/cliques por página × origem × campanha) ──

  def traffic_rows
    @traffic_rows ||= Current.account.cevico_page_traffic
                             .where(date: since_date..until_date)
                             .group(:cevico_page_id, :source, :campaign)
                             .pluck(:cevico_page_id, :source, :campaign,
                                    Arel.sql('SUM(views) AS total_views'), Arel.sql('SUM(cta_clicks) AS total_cta'))
  end

  # ── leads carimbados (Protocolo → page_ads) + jornada deles ──

  # [contact_id, page_id, source, campaign] — page_id nulo = lead do HUB
  def attributed_leads
    @attributed_leads ||= Current.account.contacts
                                 .where("additional_attributes -> 'page_ads' IS NOT NULL")
                                 .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz >= ?", since_date.beginning_of_day)
                                 .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz <= ?", until_date.end_of_day)
                                 .pluck(:id,
                                        Arel.sql("(additional_attributes -> 'page_ads' ->> 'page_id')::bigint"),
                                        Arel.sql("additional_attributes -> 'page_ads' ->> 'source'"),
                                        Arel.sql("additional_attributes -> 'page_ads' ->> 'campaign'"))
  end

  # contatos que AGENDARAM consulta (task consulta ligada ao contato)
  def booked_contact_ids
    @booked_contact_ids ||= begin
      ids = attributed_leads.map(&:first)
      ids.empty? ? Set.new : Current.account.tasks.where(task_type: 'consulta', contact_id: ids).distinct.pluck(:contact_id).to_set
    end
  end

  # mesma régua do relatório de Anúncios: etapas com "cirurgia" no nome
  # (sem as de indicação), ou as escolhidas na config do Meta Ads
  def conversion_stage_ids
    @conversion_stage_ids ||= begin
      configured = Array(meta_config['conversion_stage_ids']).map(&:to_i).reject(&:zero?)
      if configured.any?
        configured
      else
        base = Crm::Stage.joins(:pipeline)
                         .where(crm_pipelines: { account_id: Current.account.id })
                         .where('crm_stages.name ILIKE ?', '%cirurgia%')
        strict = base.where.not('crm_stages.name ILIKE ?', '%indica%').pluck(:id)
        strict.any? ? strict : base.pluck(:id)
      end
    end
  end

  # contact_id → valor do card, só de quem chegou na etapa de conversão
  def converted_values_by_contact
    @converted_values_by_contact ||= begin
      contact_ids = attributed_leads.map(&:first)
      if contact_ids.empty? || conversion_stage_ids.empty?
        {}
      else
        cards = Crm::Contact.joins(:pipeline)
                            .where(crm_pipelines: { account_id: Current.account.id })
                            .where(contact_id: contact_ids)
        converted_ids = cards.where(stage_id: conversion_stage_ids).pluck(:id) |
                        Crm::StageLog.where(crm_contact_id: cards.select(:id), stage_id: conversion_stage_ids)
                                     .pluck(:crm_contact_id)
        cards.where(id: converted_ids).pluck(:contact_id, :value).to_h
      end
    end
  end

  # ── junção por página ──

  def rows_json # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    by_page = Hash.new { |h, k| h[k] = blank_row }

    traffic_rows.each do |page_id, source, campaign, views, cta|
      row = by_page[page_id]
      row[:views] += views
      row[:cta] += cta
      src = (row[:sources][source] ||= blank_bucket)
      src[:views] += views
      src[:cta] += cta
      next if campaign.blank?

      camp = (row[:campaigns][campaign] ||= blank_bucket)
      camp[:views] += views
      camp[:cta] += cta
    end

    attributed_leads.each do |contact_id, page_id, source, campaign|
      row = by_page[page_id]
      add_lead = lambda do |bucket|
        bucket[:leads] += 1
        bucket[:booked] += 1 if booked_contact_ids.include?(contact_id)
        if converted_values_by_contact.key?(contact_id)
          bucket[:conversions] += 1
          bucket[:revenue] += converted_values_by_contact[contact_id].to_f
        end
      end
      add_lead.call(row)
      add_lead.call(row[:sources][source.presence || 'direto'] ||= blank_bucket)
      add_lead.call(row[:campaigns][campaign] ||= blank_bucket) if campaign.present?
    end

    pages_by_id = Current.account.cevico_pages
                         .select(:id, :title, :slug, :emoji, :status, :category)
                         .index_by(&:id)
    rows = by_page.filter_map do |page_id, row|
      base = row.merge(revenue: row[:revenue].round(2))
      # leads do HUB (porta de entrada, sem página) ganham linha própria
      if page_id.nil?
        next base.merge(page_id: nil, title: 'Porta de entrada (hub)', slug: '', emoji: '🚪',
                        status: 'published', category: 'captacao')
      end

      page = pages_by_id[page_id]
      next if page.nil?

      base.merge(page_id: page.id, title: page.title, slug: page.slug, emoji: page.emoji,
                 status: page.status, category: page.category)
    end
    rows.sort_by { |r| [-r[:conversions], -r[:leads], -r[:views]] }
  end

  def blank_bucket
    { views: 0, cta: 0, leads: 0, booked: 0, conversions: 0, revenue: 0.0 }
  end

  def blank_row
    blank_bucket.merge(sources: {}, campaigns: {})
  end

  # honestidade do rastreio: quantos Protocolos foram gerados no clique ×
  # quantos chegaram na caixa (paciente manteve o código na mensagem)
  def protocol_json
    refs = Current.account.cevico_page_refs
                  .where(created_at: since_date.beginning_of_day..until_date.end_of_day)
    { minted: refs.count, matched: refs.where.not(contact_id: nil).count }
  end

  def meta_config
    @meta_config ||= CrmSetting.find_by(account: Current.account)&.meta_ads_config || {}
  end
end
