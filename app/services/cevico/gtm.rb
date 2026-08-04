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
