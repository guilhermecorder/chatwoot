# 🩻 Raio-X da página (23/10 — "preciso compreender o que acontece com a página
# e em qual parte preciso realmente ajustar"): o MAPA de leitura de uma página
# anexada, lido do próprio HTML.
#
#   marcos  cada título <h2>, na ordem da página. Chave = o id do título, ou o
#           texto dele em forma de endereço ("Isso acontece com você?" →
#           "isso-acontece-com-voce").
#   botoes  cada link de conversão (WhatsApp, /cta, próximo passo ?de=). Chave
#           = o data-ev do link, ou "<marco>#<n>" (o n-ésimo botão depois
#           daquele título; "topo#n" antes do primeiro).
#   erros   (toques errados, 23/10) não estão no mapa: a chave é "<marco>~<tipo>"
#           — onde a pessoa tocou (o trecho, pelo título anterior) e no quê:
#           foto, titulo, parece-botao, texto, ou repetido (3 toques seguidos no
#           mesmo lugar). Vale se o marco existe na página e o tipo é um destes.
#
# O beacon da página (cevico_pages/_tracking_snippet) monta as MESMAS chaves no
# navegador, com as mesmas regras; o servidor só aceita chaves deste mapa — o
# endereço é público, então ninguém enche o daily_stats com lixo.
class Cevico::PageReading
  KEY = /\A[a-z0-9_-]{1,48}\z/
  CTA_HREF = %r{wa\.me/|api\.whatsapp\.com|\Awhatsapp:|/cta(\?|\z)|[?&]de=}i
  TOP = 'topo'.freeze
  MISS_TYPES = %w[foto titulo parece-botao texto repetido].freeze

  def self.miss_key?(map, key)
    marco, tipo = key.to_s.split('~', 2)
    MISS_TYPES.include?(tipo) && (marco == TOP || map['marcos'].any? { |m| m['key'] == marco })
  end

  # o mapa muda só quando a página muda: cache pela data da última edição
  def self.map_for(page)
    Rails.cache.fetch("cevico:leitura:mapa:#{page.id}:#{page.updated_at.to_i}", expires_in: 12.hours) do
      new(page.custom_html).map
    end
  end

  # igual ao slug() do beacon: sem acento, minúsculo, só letras/números/hífen, até 48
  def self.slugify(text)
    text.to_s.unicode_normalize(:nfd).gsub(/[̀-ͯ]/, '').downcase
        .gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')[0, 48].to_s.sub(/-+\z/, '')
  end

  def initialize(html)
    @doc = Nokogiri::HTML(html.to_s)
  end

  def map
    @marcos = {}
    @botoes = {}
    @atual = TOP
    @contagem = Hash.new(0)
    @doc.xpath('//h2 | //a[@href]').each { |node| node.name == 'h2' ? add_marker(node) : add_button(node) }
    { 'marcos' => @marcos.values, 'botoes' => @botoes.values }
  end

  private

  def add_marker(node)
    key = marker_key(node)
    return if key.blank?

    @atual = key
    # o id do bloco (<section id="investimento">) ajuda a reconhecer o tipo do trecho
    @marcos[key] ||= { 'key' => key, 'titulo' => clean(readable(node), 90), 'secao' => node.ancestors('section').first&.[]('id').to_s }
  end

  def add_button(node)
    return unless node['href'].to_s.match?(CTA_HREF)

    key = button_key(node)
    @botoes[key] ||= { 'key' => key, 'texto' => button_text(node), 'marco' => @atual }
  end

  def marker_key(node)
    id = node['id'].to_s
    id.match?(KEY) ? id : self.class.slugify(node.text)
  end

  def button_key(node)
    ev = node['data-ev'].to_s
    return ev if ev.match?(KEY)

    @contagem[@atual] += 1
    "#{@atual}##{@contagem[@atual]}"
  end

  # o título como a pessoa lê (o <br> vira espaço; a chave usa o texto cru, como o navegador)
  def readable(node)
    Nokogiri::HTML.fragment(node.inner_html.gsub(%r{<br\s*/?>}i, ' ')).text
  end

  # o texto do botão como aparece: pedaços separados por espaço e sem a palavra repetida das
  # versões longa/curta ("Perguntar no WhatsApp" + "WhatsApp" → "Perguntar no WhatsApp")
  def button_text(node)
    clean(node.xpath('.//text()').map(&:text).join(' '), 60).gsub(/\b(\S+)(?: \1\b)+/, '\\1')
  end

  def clean(text, max)
    text.to_s.gsub(/[[:space:]]+/, ' ').strip.truncate(max)
  end
end
