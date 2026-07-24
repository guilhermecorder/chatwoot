# Classifica de ONDE veio a visita da página, na ordem que importa pra
# clínica: Google Ads (gclid ou utm de cpc), Google orgânico (SEO — veio
# do google sem clique pago), Meta Ads (utm pago), redes sociais
# orgânicas, funil interno (?de= de outra página CEVICO) e direto.
#
# Padrão de UTM combinado pros anúncios: utm_source=google|meta,
# utm_medium=cpc, utm_campaign=nome-da-campanha (o gclid/fbclid a própria
# plataforma anexa sozinha).
module Cevico::TrafficSource
  SOURCES = {
    'google_ads' => 'Google Ads',
    'google_organico' => 'Google orgânico (SEO)',
    'meta_ads' => 'Meta Ads',
    'social' => 'Redes sociais',
    'outros_ads' => 'Outros anúncios',
    'funil' => 'Funil interno',
    'busca' => 'Outras buscas',
    'direto' => 'Direto / outros'
  }.freeze

  PAID_MEDIUMS = %w[cpc ppc paid paid_social paid_search ads ad].freeze
  GOOGLE_SOURCES = %w[google googleads google-ads adwords].freeze
  META_SOURCES = %w[meta facebook fb instagram ig].freeze
  SEARCH_HOSTS = %w[bing. duckduckgo. yahoo. brave.].freeze
  SOCIAL_HOSTS = %w[facebook. instagram. l.instagram. lm.facebook. m.facebook. t.co linkedin. youtube. tiktok.].freeze

  module_function

  # params: hash com utm_source/utm_medium/utm_campaign/gclid/fbclid/de
  # referer: request.referer (ou host salvo pelo script, em ref_host)
  # Devolve { source:, campaign: } — campaign só quando veio de utm.
  def classify(params, referer: nil)
    prm = normalize(params)
    campaign = prm['utm_campaign'].to_s.gsub(/[^\w\s.-]/, '')[0, 80]
    { source: source_key(prm, referer), campaign: campaign }
  end

  # cadeia de decisão em ordem de certeza (pago com identificador > orgânico
  # identificado > funil > direto) — a lista é o produto, não complexidade
  def source_key(prm, referer) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    host = referer_host(prm, referer)
    return 'google_ads' if prm['gclid'].present? || (GOOGLE_SOURCES.include?(prm['utm_source']) && paid?(prm))
    return 'meta_ads' if META_SOURCES.include?(prm['utm_source']) && paid?(prm)
    return 'google_organico' if host.include?('google.') || GOOGLE_SOURCES.include?(prm['utm_source'])
    return 'meta_ads' if prm['fbclid'].present? && prm['utm_source'].present? # anúncio Meta com utm próprio
    return 'social' if prm['fbclid'].present? || META_SOURCES.include?(prm['utm_source']) ||
                       SOCIAL_HOSTS.any? { |h| host.include?(h) }
    return 'outros_ads' if paid?(prm) || prm['utm_source'].present?
    return 'busca' if SEARCH_HOSTS.any? { |h| host.include?(h) }
    return 'funil' if prm['de'].present?

    'direto'
  end

  def paid?(prm)
    PAID_MEDIUMS.include?(prm['utm_medium'])
  end

  def normalize(params)
    keys = %w[utm_source utm_medium utm_campaign utm_content utm_term gclid fbclid de ref_host]
    raw = keys.index_with { |k| params[k].presence || params[k.to_sym].presence }
    normalized = raw.transform_values { |v| v.to_s.strip.downcase.presence }.compact
    # campanha preserva o nome como veio (é rótulo de relatório, não chave)
    normalized.merge('utm_campaign' => (params['utm_campaign'].presence || params[:utm_campaign]).to_s.strip)
  end

  def referer_host(prm, referer)
    return prm['ref_host'].to_s if prm['ref_host'].present?

    URI.parse(referer.to_s).host.to_s.downcase
  rescue URI::InvalidURIError
    ''
  end

  # dados que valem a pena guardar no Protocolo (pro carimbo do contato);
  # page nil = clique no HUB (porta de entrada do domínio)
  def snapshot(params, page:)
    prm = normalize(params)
    {
      'page_id' => page&.id, 'slug' => page&.slug || 'hub',
      'title' => page&.title || 'Porta de entrada (hub)',
      'source' => source_key(prm, nil), 'campaign' => prm['utm_campaign'].to_s[0, 80],
      'utm_source' => prm['utm_source'], 'utm_medium' => prm['utm_medium'],
      'utm_content' => prm['utm_content'], 'utm_term' => prm['utm_term'],
      'gclid' => (params['gclid'].presence || params[:gclid]).to_s[0, 200].presence,
      'fbclid' => (params['fbclid'].presence || params[:fbclid]).to_s[0, 200].presence
    }.compact
  end
end
