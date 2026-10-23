# 🩻 RAIO-X DE UMA PÁGINA (23/10, Biblioteca): o caminho de quem chegou, ONDE
# a página perde gente e o que mexer primeiro.
#
#   numeros      acessos → cliques → leads → agendou (Cevico::TrafficReport)
#   leitura      das visitas MEDIDAS (beacon da página anexada): quantas
#                chegaram a 25/50/75/100% da página
#   trechos      o MAPA DE CALOR: abertura + um trecho por título, com quem viu,
#                quem parou nele, toques em botões, toques errados, status e o que
#                mudar no texto (Cevico::PageSections)
#   botoes       cada botão de conversão e quantas visitas o tocaram
#   origens      de onde vieram (Google orgânico, anúncios, direto…) e quanto
#                cada origem converte
#   google       a página no Search Console (foto em cache, últimos 28 dias)
#   diagnostico  frases curtas, da mais grave para a mais leve
#
# A régua é sempre a MÉDIA DAS PRÓPRIAS PÁGINAS do mesmo tipo no período
# (anúncio com anúncio, orgânica com orgânica) — nunca um número de mercado.
# Abaixo do volume mínimo, avisa que é cedo em vez de tirar conclusão.
class Cevico::PageXray # rubocop:disable Metrics/ClassLength
  MIN_VIEWS = 30
  MIN_READS = 30
  MIN_CLICKS = 8
  MIN_LEADS = 5
  BELOW = 0.6 # bem abaixo da média = menos de 60% dela
  ABOVE = 1.3
  MARKS = %w[25 50 75 100].freeze
  LEVELS = %w[alerta atencao oportunidade info ok].freeze

  def initialize(page, since_date, until_date, rows:, ad_page_ids:)
    @page = page
    @since = since_date.iso8601
    @until = until_date.iso8601
    @rows = rows
    @ad_ids = ad_page_ids.to_set
  end

  def call
    { pagina: page_info, numeros: numbers, leitura: reading, trechos: sections.trechos, botoes: buttons,
      origens: sources, google: google, media: average, diagnostico: diagnosis, parametros: Cevico::PageSections.parameters }
  end

  private

  def ad?(page_id = @page.id)
    @ad_ids.include?(page_id)
  end

  def page_info
    { slug: @page.slug, titulo: @page.title, url: Cevico::PublicSite.page_url(@page.slug, account: @page.account),
      tipo: ad? ? 'anuncio' : 'organica', mudou_em: @page.updated_at.to_date.iso8601,
      teste_ab: @page.ab_test_running? }
  end

  def row
    @row ||= @rows.find { |r| r[:page_id] == @page.id } || { views: 0, cta: 0, leads: 0, booked: 0, sources: {} }
  end

  def numbers
    { acessos: row[:views].to_i, cliques: row[:cta].to_i, leads: row[:leads].to_i, agendou: row[:booked].to_i }
  end

  def sections
    @sections ||= Cevico::PageSections.new(@page, Date.parse(@since), Date.parse(@until))
  end

  delegate :stats, :measured, :map, to: :sections

  def reading
    total = measured
    reached = MARKS.index_with { |mark| stats['scroll'].sum { |key, n| key.to_i >= mark.to_i ? n : 0 } }
    { medidas: total, desde: stats['desde'], chegaram: reached,
      pct: reached.transform_values { |n| total.positive? ? (n.to_f / total).round(4) : nil } }
  end

  def buttons
    @buttons ||= begin
      titles = map['marcos'].to_h { |m| [m['key'], m['titulo']] }
      map['botoes'].map do |botao|
        botao.merge('cliques' => stats['botoes'][botao['key']], 'marco_titulo' => titles[botao['marco']] || 'Abertura (primeira tela)')
      end
    end
  end

  def sources
    list = (row[:sources] || {}).map do |key, bucket|
      { key: key, nome: Cevico::TrafficSource::SOURCES[key] || key, acessos: bucket[:views].to_i,
        cliques: bucket[:cta].to_i, leads: bucket[:leads].to_i, agendou: bucket[:booked].to_i }
    end
    list.sort_by { |src| [-src[:acessos], -src[:leads]] }
  end

  def google
    cache = Cevico::SearchConsole.new(@page.account).cache
    found = Array(cache['pages']).find { |r| path_of(r['url']) == "/#{@page.slug}" }
    return nil if found.nil?

    { impressoes: found['impressions'].to_i, cliques: found['clicks'].to_i, ctr: found['ctr'].to_f,
      posicao: found['position'], janela: cache['window'] }
  rescue StandardError
    nil
  end

  def path_of(url)
    URI.parse(url.to_s).path.to_s.delete_suffix('/')
  rescue URI::InvalidURIError
    nil
  end

  # médias das páginas do MESMO tipo, com volume mínimo (somas, não média de taxas)
  def average
    @average ||= begin
      peers = @rows.select { |r| r[:page_id] && ad?(r[:page_id]) == ad? && r[:views].to_i >= MIN_VIEWS }
      sum = ->(key) { peers.sum { |r| r[key].to_i } }
      { tipo: ad? ? 'anuncio' : 'organica', paginas: peers.size,
        tx_clique: ratio(sum.call(:cta), sum.call(:views)), tx_lead: ratio(sum.call(:leads), sum.call(:cta)),
        tx_agenda: ratio(sum.call(:booked), sum.call(:leads)) }
    end
  end

  def ratio(part, whole)
    whole.to_i.positive? ? (part.to_f / whole).round(4) : nil
  end

  # ── diagnóstico ───────────────────────────────────────────────────────
  def diagnosis
    list = []
    if numbers[:acessos] < MIN_VIEWS
      list << volume_note
    else
      list.concat(reading_notes)
      list.concat(funnel_notes)
      list.concat(button_notes)
    end
    list.concat(google_notes)
    list << item('ok', 'Nada fora do normal no período', 'Os números desta página estão na média das outras do mesmo tipo.') if list.empty?
    list.sort_by { |d| LEVELS.index(d[:nivel]) }
  end

  def volume_note
    where = if ad?
              'Aqui o trabalho é o anúncio: verba, público e o criativo que leva para a página.'
            else
              'Aqui o trabalho é aparecer: Google (indexação, título que responde à busca) e links de outras páginas.'
            end
    item('info', 'Ainda pouca visita para tirar conclusões',
         "#{numbers[:acessos] == 1 ? 'Foi 1 acesso' : "Foram #{numbers[:acessos]} acessos"} no período " \
         "(o mínimo para comparar é #{MIN_VIEWS}). #{where}")
  end

  def reading_notes # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return [] if measured < MIN_READS

    notes = []
    flagged = sections.trechos.select { |t| Cevico::PageSections::FLAGGED.include?(t['status']) }
    worst = flagged.select { |t| t['saida'] }.max_by { |t| t['perdidas'] }
    if worst
      notes << item(worst['status'] == 'problema' ? 'alerta' : 'atencao', "Onde mais gente para de ler: “#{worst['titulo']}”",
                    "De quem chega neste trecho, #{pct(worst['saida'])} para de ler nele (#{worst['perdidas']} visitas no período). " \
                    'É o primeiro trecho a reescrever: veja o que mudar no mapa de calor.')
    end
    missed = flagged.select { |t| t['erros_total'].positive? }.max_by { |t| t['erros_total'] }
    if missed && missed['motivos'].any? { |m| m.include?('toque errado') }
      notes << item('atencao', "Toques errados em “#{missed['titulo']}”",
                    "#{missed['erros_total']} visitas tocaram onde nada acontece neste trecho. Veja onde no mapa de calor.")
    end
    half = reading[:pct]['50']
    if half && half < 0.4
      notes << item('atencao', 'A maioria sai antes da metade',
                    "Só #{pct(half)} das visitas chegam à metade da página. A abertura promete o que a pessoa buscou?")
    end
    finish = reading[:pct]['100']
    click = ratio(numbers[:cliques], numbers[:acessos])
    if finish && finish >= 0.4 && click && average[:tx_clique] && click < average[:tx_clique] * BELOW
      notes << item('atencao', 'Leem até o fim e não clicam',
                    "#{pct(finish)} chegam ao fim, mas só #{pct(click)} clicam. O convite final não está convencendo.")
    end
    notes
  end

  def funnel_notes # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    notes = []
    click = ratio(numbers[:cliques], numbers[:acessos])
    avg = average[:tx_clique]
    if click && avg&.positive?
      if click < avg * BELOW
        notes << item('alerta', 'Poucos clicam no WhatsApp',
                      "#{pct(click)} das visitas clicam, contra #{pct(avg)} na média das páginas do mesmo tipo.")
      elsif click > avg * ABOVE
        notes << item('ok', 'Clique acima da média', "#{pct(click)} das visitas clicam (média #{pct(avg)}).")
      end
    end
    lead = ratio(numbers[:leads], numbers[:cliques])
    if numbers[:cliques] >= MIN_CLICKS && lead && average[:tx_lead]&.positive? && lead < average[:tx_lead] * BELOW
      notes << item('alerta', 'Clicam e não mandam a mensagem',
                    "De #{numbers[:cliques]} cliques, #{numbers[:leads]} viraram conversa (#{pct(lead)}; média #{pct(average[:tx_lead])}). " \
                    'Conferir a mensagem pronta e o número do WhatsApp desta página.')
    end
    booked = ratio(numbers[:agendou], numbers[:leads])
    if numbers[:leads] >= MIN_LEADS && booked && average[:tx_agenda]&.positive? && booked < average[:tx_agenda] * BELOW
      notes << item('atencao', 'Os leads desta página agendam pouco',
                    "#{pct(booked)} dos leads agendaram (média #{pct(average[:tx_agenda])}). " \
                    'A página promete algo que o atendimento não confirma?')
    end
    notes
  end

  def button_notes # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    total = buttons.sum { |b| b['cliques'] }
    return [] if total < MIN_CLICKS

    notes = []
    top = buttons.max_by { |b| b['cliques'] }
    if top['cliques'].to_f / total >= 0.5
      notes << item('info', 'Metade dos cliques vem de um botão só',
                    "“#{top['texto'].presence || top['key']}” (abaixo de “#{top['marco_titulo']}”) traz " \
                    "#{pct(top['cliques'].to_f / total)} dos cliques.")
    end
    idle = buttons.select { |b| b['cliques'].zero? }
    if buttons.size >= 3 && idle.size.positive? && measured >= 50
      names = idle.first(3).map { |b| "“#{b['texto'].presence || b['key']}”" }.join(', ')
      notes << item('oportunidade', 'Botões que ninguém tocou', "#{names}. Vale mudar o texto, o lugar ou tirar.")
    end
    notes
  end

  def google_notes # rubocop:disable Metrics/CyclomaticComplexity
    gsc = google
    return [] if gsc.nil? || ad?

    notes = []
    if gsc[:impressoes] >= 100 && gsc[:ctr] < 1
      notes << item('atencao', 'Aparece no Google e quase ninguém clica',
                    "#{gsc[:impressoes]} aparições e #{gsc[:cliques]} cliques (#{format('%.1f', gsc[:ctr]).tr('.', ',')}%). " \
                    'O título e a descrição na busca precisam responder melhor à pergunta.')
    end
    if gsc[:posicao]&.between?(8, 20) && gsc[:impressoes] >= 30
      notes << item('oportunidade', 'Quase na 1ª página do Google',
                    "Posição média #{format('%.1f', gsc[:posicao]).tr('.', ',')}. " \
                    'Reforçar o conteúdo e receber links de outros guias pode levar à 1ª página.')
    end
    notes
  end

  def item(level, title, text)
    { nivel: level, titulo: title, texto: text }
  end

  def pct(value)
    number = value.to_f * 100
    "#{number < 10 ? format('%.1f', number).tr('.', ',') : number.round}%"
  end
end
