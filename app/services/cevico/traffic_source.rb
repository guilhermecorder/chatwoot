# Classifica de ONDE veio a visita da página, na ordem que importa pra
# clínica: Google Ads (gclid ou utm de cpc), Google orgânico (SEO — veio
# do google sem clique pago), Meta Ads (utm pago), redes sociais
# orgânicas, funil interno (?de= de outra página CEVICO) e direto.
#
# Padrão de UTM combinado pros anúncios: utm_source=google|meta,
# utm_medium=cpc, utm_campaign=nome-da-campanha (o gclid/fbclid a própria
# plataforma anexa sozinha).
module Cevico::TrafficSource # rubocop:disable Metrics/ModuleLength
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
  # códigos de clique do Google Ads: gclid (o comum) e gbraid/wbraid (o que o
  # Google manda no lugar dele em iPhone) — item 313
  GOOGLE_CLICK_IDS = %w[gclid gbraid wbraid].freeze
  # código de clique é comprido (o da Meta passa de 150 letras); cortado, não serve
  CLICK_ID_MAX = 500
  SOCIAL_HOSTS = %w[facebook. instagram. l.instagram. lm.facebook. m.facebook. t.co linkedin. youtube. tiktok.].freeze

  # 🧭 item 385 (04/11): REGRAS DO GUILHERME por cima das automáticas — "quando
  # utm_source for X (e utm_medium Y, e o site de onde veio Z) → conta como
  # Google Ads / Meta Ads / SEO / Redes sociais / Outros anúncios". Ficam em
  # google_ads_config['traffic_source_rules'] e valem nas visitas novas E nos
  # leads já carimbados (a origem é recalculada na leitura pelos utm guardados).
  RULE_FIELDS = %w[utm_source utm_medium utm_campaign host].freeze
  MAX_RULES = 30

  module_function

  # params: hash com utm_source/utm_medium/utm_campaign/gclid/fbclid/de
  # referer: request.referer (ou host salvo pelo script, em ref_host)
  # account: lê as regras do Guilherme (sem conta = só as automáticas)
  # Devolve { source:, campaign: } — campaign só quando veio de utm.
  def classify(params, referer: nil, account: nil)
    prm = normalize(params)
    campaign = prm['utm_campaign'].to_s.gsub(/[^\w\s.-]/, '')[0, 80]
    { source: source_key(prm, referer, rules: rules_for(account)), campaign: campaign }
  end

  def rules_for(account)
    return [] if account.nil?

    cfg = CrmSetting.find_by(account_id: account.id)&.google_ads_config || {}
    sanitize_rules(cfg['traffic_source_rules'])
  rescue StandardError
    []
  end

  # o que a tela manda → o que fica gravado: [{ 'quando' => { utm_source:, utm_medium:, utm_campaign:, host: }, 'origem' => chave }]
  def sanitize_rules(raw) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    Array(raw).filter_map do |r|
      r = r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r
      next unless r.is_a?(Hash)

      r = r.transform_keys(&:to_s)
      quando = (r['quando'].respond_to?(:to_unsafe_h) ? r['quando'].to_unsafe_h : r['quando']).to_h.transform_keys(&:to_s)
      quando = RULE_FIELDS.index_with { |k| quando[k].to_s.strip.downcase[0, 80].presence }.compact
      next if quando.empty? || !SOURCES.key?(r['origem'].to_s)

      { 'quando' => quando, 'origem' => r['origem'].to_s }
    end.first(MAX_RULES)
  end

  # a regra que bate (todos os campos preenchidos têm que bater; host = contém)
  def custom_source(prm, host, rules)
    Array(rules).each_with_index do |rule, i|
      q = rule['quando']
      ok = q.all? do |k, v|
        k == 'host' ? host.to_s.include?(v) : prm[k].to_s == v
      end
      return [rule['origem'], i + 1] if ok
    end
    nil
  end

  # origem de um lead JÁ carimbado (page_ads), com as regras de hoje por cima
  def effective_source(data, rules)
    return data['source'].presence || 'direto' if rules.blank? || !data.is_a?(Hash)

    prm = data.slice(*RULE_FIELDS).transform_values { |v| v.to_s.downcase }
    hit = custom_source(prm, data['ref_host'].to_s, rules)
    hit ? hit.first : (data['source'].presence || 'direto')
  end

  # POR QUÊ a visita foi classificada assim — texto para a tela (item 385)
  def reason(data, rules = []) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'sem rastro' unless data.is_a?(Hash)

    prm = data.slice(*RULE_FIELDS).transform_values { |v| v.to_s.downcase }
    hit = custom_source(prm, data['ref_host'].to_s, rules)
    return "regra sua nº #{hit.last}" if hit

    utm = %w[utm_source utm_medium].filter_map { |k| "#{k}=#{data[k]}" if data[k].present? }.join(' · ')
    return "gclid/gbraid (clique no anúncio do Google)#{utm.present? ? " · #{utm}" : ''}" if GOOGLE_CLICK_IDS.any? { |k| data[k].present? }
    return "#{utm} (anúncio)" if utm.present? && PAID_MEDIUMS.include?(data['utm_medium'].to_s.downcase)
    return "veio de #{data['ref_host']} (busca sem anúncio)" if data['ref_host'].to_s.include?('google.')
    return "fbclid (clique na Meta)#{utm.present? ? " · #{utm}" : ''}" if data['fbclid'].present?
    return utm if utm.present?
    return "veio de #{data['ref_host']}" if data['ref_host'].present?
    return "veio da página #{data['de']}" if data['de'].present?

    'link direto, sem utm'
  end

  # cadeia de decisão em ordem de certeza (regra do Guilherme > pago com
  # identificador > orgânico identificado > funil > direto)
  def source_key(prm, referer, rules: []) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    host = referer_host(prm, referer)
    custom = custom_source(prm, host, rules)
    return custom.first if custom
    return 'google_ads' if GOOGLE_CLICK_IDS.any? { |k| prm[k].present? } || (GOOGLE_SOURCES.include?(prm['utm_source']) && paid?(prm))
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

  # só dígitos (o {campaignid} do Google é numérico); outra coisa não junta com o custo
  def campaign_id(value)
    value.to_s[/\A\d{4,20}\z/]
  end

  def paid?(prm)
    PAID_MEDIUMS.include?(prm['utm_medium'])
  end

  def normalize(params)
    keys = %w[utm_source utm_medium utm_campaign utm_id utm_content utm_term gclid gbraid wbraid fbclid de ref_host]
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
  # cookies: os do navegador na hora do clique (reserva para quando o script
  # da página não mandou a identidade — ex.: botão /cta das páginas montadas)
  # ga4_id: a propriedade do Analytics que RECEBE as conversões do CRM — a
  # sessão guardada é a dela (a página pode medir em mais de uma)
  def snapshot(params, page:, cookies: nil, ga4_id: nil, referer: nil, account: nil) # rubocop:disable Metrics/ParameterLists
    prm = normalize(params)
    host = referer_host(prm, referer)
    {
      'page_id' => page&.id, 'slug' => page&.slug || 'hub',
      'title' => page&.title || 'Porta de entrada (hub)',
      'source' => source_key(prm, referer, rules: rules_for(account || page&.account)), 'campaign' => prm['utm_campaign'].to_s[0, 80],
      # 🧭 item 385: de onde o visitante veio (para explicar a origem e aplicar regras novas depois)
      'ref_host' => host.presence, 'de' => prm['de'],
      'utm_source' => prm['utm_source'], 'utm_medium' => prm['utm_medium'],
      # ID da campanha no Google Ads (sufixo do URL final: utm_id={campaignid}) — é a
      # chave que junta o lead ao custo da campanha no ROI por campanha (18/10)
      'utm_id' => campaign_id(prm['utm_id']),
      'utm_content' => prm['utm_content'], 'utm_term' => prm['utm_term']
    }.merge(click_ids(params, cookies, ga4_id)).compact
  end

  # ids de clique/sessão que amarram o lead ao anúncio: gclid/fbclid (da URL)
  # e a identidade GA4 do navegador (cookies _ga/_ga_*) — é o que permite
  # devolver a conversão AMARRADA à sessão que clicou no anúncio; sem isso
  # o Google Ads não atribui (missão 03/08)
  def click_ids(params, cookies = nil, ga4_id = nil)
    jar = cookies.respond_to?(:to_h) ? cookies.to_h.transform_keys(&:to_s) : {}
    ad_click_ids(params).merge(google_identity(params, jar, ga4_id)).merge(meta_identity(params, jar))
  end

  def ad_click_ids(params)
    (GOOGLE_CLICK_IDS + %w[fbclid]).index_with { |key| raw_param(params, key)[0, CLICK_ID_MAX].presence }
  end

  # identidade do navegador no Google Analytics: a que a página mandou vence;
  # sem ela, a dos cookies. Sessão: a da propriedade que recebe as conversões
  # vence (com mais de um Analytics na página, cada um tem a sua).
  def google_identity(params, jar, ga4_id = nil)
    own_cookie = ga4_id.to_s.strip.upcase.delete_prefix('G-').presence&.then { |suffix| jar["_ga_#{suffix}"] }
    {
      'ga_client_id' => raw_param(params, 'ga_client_id')[0, 64].presence || ga_client_id_from(jar),
      'ga_session_id' => ga_session_id(own_cookie) || raw_param(params, 'ga_session_id')[0, 32].presence || ga_session_id_from(jar)
    }
  end

  # identidade do navegador no Pixel da Meta (cookies _fbp/_fbc)
  def meta_identity(params, jar)
    {
      'fbp' => (raw_param(params, 'fbp').presence || jar['_fbp']).to_s[0, 100].presence,
      'fbc' => (raw_param(params, 'fbc').presence || jar['_fbc']).to_s[0, CLICK_ID_MAX + 40].presence
    }
  end

  # cookie _ga = "GA1.1.<identidade>" — a identidade é o que o GA4 chama de client_id
  def ga_client_id_from(jar)
    jar['_ga'].to_s[/\AGA\d+\.\d+\.(.+)\z/, 1].to_s[0, 64].presence
  end

  # cookie _ga_<propriedade> = "GS1.1.<sessão>.…" (formato antigo) ou
  # "GS2.1.s<sessão>$…" (formato novo, 2025)
  def ga_session_id(cookie_value)
    cookie_value.to_s[/\AGS\d+\.\d+\.s?(\d+)/, 1].to_s[0, 32].presence
  end

  def ga_session_id_from(jar)
    ga_session_id(jar.find { |name, _v| name.start_with?('_ga_') }&.last)
  end

  def raw_param(params, key)
    (params[key].presence || params[key.to_sym]).to_s
  end
end
