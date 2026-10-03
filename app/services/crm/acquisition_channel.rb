# 🧭 De ONDE veio o paciente, para o CAC por canal (item 318, 03/10/2026).
# Primeiro toque — o carimbo mais antigo do contato vence:
#   meta_ads (clique no anúncio que abre o WhatsApp — Crm::AdAttributionService)
#     → Meta, campanha pelo anúncio (Crm::AdCreative)
#   page_ads (landing page — Crm::PageAttributionService / Cevico::TrafficSource)
#     → google_ads = Google · meta_ads = Meta · o resto = orgânico (com o detalhe)
#   nenhum carimbo → orgânico / indicação (WhatsApp direto, indicação, balcão…)
class Crm::AcquisitionChannel
  CHANNELS = {
    'google' => 'Google Ads',
    'meta' => 'Meta Ads',
    'organico' => 'Orgânico / indicação'
  }.freeze
  PAID = %w[google meta].freeze
  NO_TRACE = 'sem rastro de anúncio (indicação, WhatsApp direto, balcão)'.freeze
  NO_CAMPAIGN = '(campanha não identificada)'.freeze

  Result = Struct.new(:channel, :detail, :campaign, :ad_id, keyword_init: true)

  def initialize(account)
    @account = account
  end

  # { contact_id => Result } — numa consulta só
  def for_contacts(ids)
    rows = @account.contacts.where(id: ids.compact.uniq)
                   .pluck(:id, Arel.sql("additional_attributes->'meta_ads'"), Arel.sql("additional_attributes->'page_ads'"))
    preload_ads(rows.map { |_, meta, _| as_hash(meta)['source_id'] })
    rows.to_h { |id, meta, page| [id, classify(as_hash(meta), as_hash(page))] }
  end

  def classify(meta, page)
    touches = []
    touches << [meta['captured_at'].to_s, meta_touch(meta)] if meta['source_id'].present? || meta['ctwa_clid'].present?
    touches << [page['captured_at'].to_s, page_touch(page)] if page['source'].present?
    return Result.new(channel: 'organico', detail: NO_TRACE) if touches.empty?

    # sem data vai para o fim (o carimbo com data é o mais confiável)
    touches.min_by { |at, _| at.presence || '9999' }.last
  end

  private

  def meta_touch(meta)
    ad_id = meta['source_id'].to_s.presence
    Result.new(channel: 'meta', detail: 'clique no anúncio → WhatsApp', ad_id: ad_id,
               campaign: ad_campaigns[ad_id].presence || NO_CAMPAIGN)
  end

  def page_touch(page)
    source = page['source'].to_s
    campaign = page['campaign'].to_s.strip.presence
    case source
    when 'google_ads' then Result.new(channel: 'google', detail: 'landing page (Google Ads)', campaign: campaign || NO_CAMPAIGN)
    when 'meta_ads' then Result.new(channel: 'meta', detail: 'landing page (Meta Ads)', campaign: campaign || NO_CAMPAIGN)
    else
      Result.new(channel: 'organico', detail: Cevico::TrafficSource::SOURCES[source] || source.presence || NO_TRACE)
    end
  end

  def preload_ads(ad_ids)
    ids = ad_ids.compact.uniq - ad_campaigns.keys
    return if ids.empty?

    Crm::AdCreative.where(account_id: @account.id, ad_id: ids)
                   .pluck(:ad_id, :campaign_name, :campaign_id)
                   .each { |ad, name, cid| ad_campaigns[ad] = name.presence || cid }
  end

  def ad_campaigns
    @ad_campaigns ||= {}
  end

  def as_hash(value)
    value = JSON.parse(value) if value.is_a?(String)
    value.is_a?(Hash) ? value : {}
  rescue JSON::ParserError
    {}
  end
end
