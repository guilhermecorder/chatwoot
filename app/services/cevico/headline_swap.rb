# 🧪 item 306 (01/10): teste A/B em página HTML ANEXADA. A variação troca o
# texto do PRIMEIRO <h1> (a headline da primeira dobra) e mais nada — a
# etiqueta, o texto de apoio e os botões ficam como estão na página.
# - *asteriscos* marcam o trecho de destaque (vira o <span> que a página já
#   pinta com o degradê);
# - headline comprida ganha letra menor para o botão não descer da dobra.
# Sem <h1> ou sem título na variação, devolve o HTML intocado.
module Cevico::HeadlineSwap
  module_function

  H1 = %r{(<h1\b[^>]*>)(.*?)(</h1>)}mi
  # "Enxergar bem, o novo normal." tem 28 letras — até aqui o tamanho original cabe
  MEDIUM = 34
  LONG = 55
  SIZE_MEDIUM = 'font-size:clamp(2rem,4.8vw,3.3rem);line-height:1.1;text-wrap:balance'.freeze
  SIZE_LONG = 'font-size:clamp(1.8rem,4.2vw,2.9rem);line-height:1.12;text-wrap:balance'.freeze

  def call(html, title)
    text = title.to_s.strip
    return html if text.blank?

    html.sub(H1) { "#{open_tag(Regexp.last_match(1), text)}#{markup(text)}#{Regexp.last_match(3)}" }
  end

  # texto do admin vira HTML seguro; só o *destaque* ganha marcação
  def markup(text)
    CGI.escapeHTML(text).gsub(/\*(.+?)\*/) { "<span>#{Regexp.last_match(1)}</span>" }
  end

  def open_tag(tag, text)
    size = size_for(text.delete('*').length)
    return tag if size.nil? || tag.match?(/\sstyle\s*=/i)

    tag.sub(/>\z/, " style=\"#{size}\">")
  end

  def size_for(length)
    return nil if length <= MEDIUM

    length > LONG ? SIZE_LONG : SIZE_MEDIUM
  end
end
