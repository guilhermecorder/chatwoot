# Google Tag Manager nas páginas HTML anexadas: injeta o container nos
# lugares que o Google pede — script o mais alto possível no <head>
# (fallbacks: antes do </head>; sem head, topo do documento) e o noscript
# logo após a abertura do <body>. O id vem do card 📊 de Configurações →
# Domínio (CEVICO_TRACKING.gtm_id); sem id, devolve o HTML intocado.
module Cevico::Gtm
  module_function

  def inject(html)
    head_snippet = ApplicationController.render(partial: 'cevico_pages/gtm_head')
    return html if head_snippet.strip.blank? # sem GTM configurado

    noscript = ApplicationController.render(partial: 'cevico_pages/gtm_noscript')
    with_noscript(with_head(html, head_snippet), noscript)
  end

  # Item 313: as propriedades do Analytics (G-…) que o contêiner do GTM
  # carrega nas páginas — lidas do próprio arquivo público do contêiner. É
  # como a Conferência descobre se a página mede na MESMA propriedade que
  # recebe as conversões do CRM. Só resposta boa fica guardada (1 h).
  def ga4_ids(gtm_id)
    id = gtm_id.to_s.strip.upcase
    return [] unless id.match?(/\AGTM-[A-Z0-9]{4,12}\z/)

    cached = Rails.cache.read("cevico:gtm_ga4_ids:#{id}")
    return cached if cached

    response = HTTParty.get("https://www.googletagmanager.com/gtm.js?id=#{id}", timeout: 8)
    return [] unless response.success?

    response.body.to_s.scan(/"(G-[A-Z0-9]{6,14})"/).flatten.uniq.tap do |ids|
      Rails.cache.write("cevico:gtm_ga4_ids:#{id}", ids, expires_in: 1.hour)
    end
  rescue StandardError => e
    Rails.logger.warn "[Cevico::Gtm] não li o contêiner #{id}: #{e.message}"
    []
  end

  def with_head(html, snippet)
    return html.sub(/<head[^>]*>/i) { |tag| "#{tag}\n#{snippet}" } if html.match?(/<head[^>]*>/i)
    return html.sub(%r{</head>}i) { "#{snippet}</head>" } if html.match?(%r{</head>}i)

    snippet + html
  end

  def with_noscript(html, snippet)
    return html.sub(/<body[^>]*>/i) { |tag| "#{tag}\n#{snippet}" } if html.match?(/<body[^>]*>/i)

    html + snippet
  end
end
