# 💡 DIAGNÓSTICOS AUTOMÁTICOS das Páginas (item 329, 05/10 — "precisamos poder
# otimizar a página; um ambiente com coleta de insights").
#
# Lê os números do período (Cevico::TrafficReport) e aponta, página por
# página, ONDE o funil está vazando e o que fazer. São regras simples, sem IA,
# para a pessoa entender e conferir a conta:
#
#   cta_baixo            muita visita, pouco clique no WhatsApp
#   leitura_curta        a maioria sai antes da metade da página
#   le_e_nao_clica       leem até o fim e não clicam
#   protocolo_perdido    clicam no WhatsApp e não chegam na caixa
#   lead_nao_agenda      os leads desta página agendam pouco
#   anuncio_sem_retorno  visita paga que não vira lead
#   origem_destaque      uma origem converte bem mais do que a média da página
#   sem_visita           publicada e sem visita no período
#   seo_*                título / descrição / palavras-chave / sem Google orgânico
#   gsc_*                do Search Console (16/10): aparece muito e ninguém clica
#                        (título/descrição), quase na 1ª página (posição 8–20 →
#                        reforçar conteúdo e links), termo que traz clique e não
#                        tem página própria (sugerir página nova)
#   campea               a página que mais converte (modelo para as outras)
#
# A régua de comparação é a MÉDIA DAS PRÓPRIAS PÁGINAS no período — nunca um
# número de mercado inventado. E só fala quando há volume mínimo (abaixo disso
# é ruído): MIN_VIEWS visitas, MIN_CLICKS cliques, MIN_LEADS leads.
class Cevico::PageInsights # rubocop:disable Metrics/ClassLength
  MIN_VIEWS = 30
  MIN_CLICKS = 8
  MIN_LEADS = 5
  BELOW = 0.6 # "bem abaixo da média" = menos de 60% dela
  PAID = %w[google_ads meta_ads outros_ads].freeze
  LEVELS = { 'alerta' => 300, 'atencao' => 200, 'oportunidade' => 100, 'seo' => 50 }.freeze
  TITLE_MAX = 60
  DESCRIPTION_RANGE = (70..160)
  # Search Console: volume mínimo (abaixo disso o Google ainda está "testando" a página)
  MIN_IMPRESSIONS = 100
  MIN_IMPRESSIONS_NEAR = 30
  MIN_TERM_CLICKS = 3
  NEAR_TOP = (8.0..20.0)
  # palavras que não dizem o assunto da busca (ficam fora da conta de "tem página própria?")
  STOPWORDS = %w[a o e de da do das dos em no na nos nas um uma para pra por com sem que qual quais quanto
                 quanta como onde quando se ou ao aos sp sao paulo the].to_set.freeze
  BRAND = /cevico/i

  def initialize(rows:, totals:, search_console: nil)
    @rows = rows
    @totals = totals
    @gsc = search_console&.dig(:ready) ? search_console : nil
  end

  def call
    list = @rows.flat_map { |row| page_insights(row) }
    list << champion
    list.concat(search_console_insights) if @gsc
    list.compact.sort_by { |insight| -insight[:weight] }
  end

  private

  def page_insights(row)
    return [] if row[:page_id].nil? # a porta de entrada (hub) não é página editável

    [click_rule(row), reading_rule(row), protocol_rule(row), booking_rule(row), idle_rule(row)] +
      source_rules(row) + seo_rules(row)
  end

  # ── as médias das próprias páginas ────────────────────────────────────
  def avg_click
    @avg_click ||= rate(@totals[:cta], @totals[:views])
  end

  def avg_booked
    @avg_booked ||= rate(@totals[:booked], @totals[:leads])
  end

  # ── regras do funil ───────────────────────────────────────────────────
  def click_rule(row)
    mine = rate(row[:cta], row[:views])
    return unless row[:views] >= MIN_VIEWS && avg_click.positive? && mine < avg_click * BELOW

    gain = (((avg_click - mine) / 100.0) * row[:views]).round
    build(row, 'cta_baixo', 'alerta', 'Muita visita, pouco clique no WhatsApp',
          "#{row[:views]} visitas viraram #{row[:cta]} clique(s) no WhatsApp (#{pct(mine)}). " \
          "A média das suas páginas no período é #{pct(avg_click)}.",
          'Suba o botão do WhatsApp para a primeira tela, repita o convite no meio da página ' \
          'e deixe a chamada dizer o que a pessoa ganha ao clicar.',
          gain: gain.positive? ? "+#{gain} clique(s) no período se chegasse na média" : nil, bonus: gain)
  end

  def reading_rule(row) # rubocop:disable Metrics/AbcSize
    scroll = row[:scroll] || {}
    return if row[:views] < MIN_VIEWS || scroll.empty?

    half = rate(scroll['50'], row[:views])
    finish = rate(scroll['100'], row[:views])
    if half < 40
      build(row, 'leitura_curta', 'atencao', 'A maioria sai antes da metade da página',
            "De #{row[:views]} visitas, #{scroll['50']} chegaram à metade (#{pct(half)}) e #{scroll['100']} ao fim (#{pct(finish)}).",
            'O começo não está segurando. Troque o título por uma promessa clara, leve a prova ' \
            '(depoimento, número) e o botão para o topo e corte o que atrasa.')
    elsif finish >= 35 && rate(row[:cta], row[:views]) < avg_click
      build(row, 'le_e_nao_clica', 'atencao', 'Leem até o fim e não clicam',
            "#{pct(finish)} das visitas chegam ao fim da página, mas só #{pct(rate(row[:cta], row[:views]))} clicam no WhatsApp.",
            'O conteúdo convence; o convite final, não. Termine com um botão grande, uma frase dizendo ' \
            'o que acontece depois do clique e tire as distrações do rodapé.')
    end
  end

  def protocol_rule(row)
    arrived = rate(row[:leads], row[:cta])
    return unless row[:cta] >= MIN_CLICKS && arrived < 40

    build(row, 'protocolo_perdido', 'alerta', 'Clicam no WhatsApp e não chegam na caixa',
          "#{row[:cta]} clique(s) viraram #{row[:leads]} lead(s) na caixa (#{pct(arrived)}).",
          'A pessoa abre o WhatsApp e desiste, ou apaga o código do Protocolo antes de enviar. ' \
          'Deixe a mensagem pronta curta e natural, com o Protocolo no fim, ' \
          'e confira se o número do botão está certo e respondendo.',
          bonus: row[:cta] - row[:leads])
  end

  def booking_rule(row)
    mine = rate(row[:booked], row[:leads])
    return unless row[:leads] >= MIN_LEADS && avg_booked.positive? && mine < avg_booked * BELOW

    build(row, 'lead_nao_agenda', 'atencao', 'Os leads desta página agendam pouco',
          "#{row[:leads]} lead(s) e #{row[:booked]} agendaram (#{pct(mine)}). A média das suas páginas é #{pct(avg_booked)}.",
          'A página pode estar prometendo algo que o atendimento não confirma. ' \
          'Alinhe a promessa com o Roteiro do atendimento e leia as conversas desses leads.')
  end

  def idle_rule(row)
    return unless row[:idle] && row[:age_days].to_i >= 7

    build(row, 'sem_visita', 'atencao', 'Publicada e sem visita no período',
          'Nenhum anúncio, link ou busca trouxe gente para esta página no período.',
          'Aponte um anúncio para ela, ligue a página num funil ou divulgue o link. Se não faz mais sentido, despublique.')
  end

  # ── regras por origem ─────────────────────────────────────────────────
  def source_rules(row)
    page_rate = rate(row[:leads], row[:views])
    (row[:sources] || {}).flat_map do |source, bucket|
      [paid_rule(row, source, bucket), standout_rule(row, source, bucket, page_rate)]
    end
  end

  def paid_rule(row, source, bucket)
    return unless PAID.include?(source) && bucket[:views] >= MIN_VIEWS && bucket[:leads].zero?

    build(row, "anuncio_sem_retorno:#{source}", 'alerta', "#{label(source)}: visita paga que não vira lead",
          "#{bucket[:views]} visitas vindas de #{label(source)}, #{bucket[:cta]} clique(s) e nenhum lead na caixa.",
          'O anúncio pode estar trazendo a pessoa errada ou prometendo outra coisa. Confira as palavras-chave ' \
          'e o público, e faça o título da página repetir a promessa do anúncio.',
          bonus: bucket[:views])
  end

  def standout_rule(row, source, bucket, page_rate)
    mine = rate(bucket[:leads], bucket[:views])
    return unless bucket[:views] >= 20 && bucket[:leads] >= 3 && page_rate.positive? && mine >= page_rate * 2

    times = (mine / page_rate).round(1).to_s.tr('.', ',')
    build(row, "origem_destaque:#{source}", 'oportunidade', "#{label(source)} converte #{times} vezes mais nesta página",
          "#{bucket[:leads]} lead(s) em #{bucket[:views]} visitas (#{pct(mine)}) contra #{pct(page_rate)} da página inteira.",
          'Vale colocar mais esforço nessa origem (verba ou conteúdo) antes de mexer na página.')
  end

  # ── SEO (como a página aparece no Google) ─────────────────────────────
  def seo_rules(row)
    seo = row[:seo]
    return [] if seo.nil? || row[:status] != 'published'

    [seo_title_rule(row, seo), seo_description_rule(row, seo), seo_keywords_rule(row, seo), seo_organic_rule(row)]
  end

  def seo_title_rule(row, seo)
    size = seo[:title].length
    if size.zero?
      build(row, 'seo_titulo', 'seo', 'Sem título para o Google',
            'A página não tem o título que aparece no resultado da busca.',
            'Escreva um título de até 60 letras com a palavra principal no começo (ex.: "Cirurgia de catarata em São Paulo").')
    elsif size > TITLE_MAX
      build(row, 'seo_titulo', 'seo', "Título do Google longo demais (#{size} letras)",
            "O Google corta por volta de #{TITLE_MAX} letras: \"#{seo[:title][0, 80]}\".",
            'Encurte e deixe a palavra principal no começo.')
    end
  end

  def seo_description_rule(row, seo)
    size = seo[:description].length
    return if DESCRIPTION_RANGE.cover?(size)

    if size.zero?
      build(row, 'seo_descricao', 'seo', 'Sem descrição para o Google',
            'Sem descrição, o Google escolhe um trecho qualquer da página para mostrar na busca.',
            'Escreva 2 linhas (70 a 160 letras) dizendo o que a pessoa encontra e por que clicar.')
    else
      build(row, 'seo_descricao', 'seo', "Descrição do Google #{size < DESCRIPTION_RANGE.min ? 'curta' : 'longa'} demais (#{size} letras)",
            'O ideal fica entre 70 e 160 letras — menos que isso desperdiça espaço; mais, o Google corta.',
            'Ajuste a descrição para caber nesse tamanho, com a palavra principal e um convite.')
    end
  end

  def seo_keywords_rule(row, seo)
    return if seo[:keywords].any?

    build(row, 'seo_palavras', 'seo', 'Sem palavras-chave definidas',
          'A página não diz por quais buscas quer ser encontrada.',
          'Defina de 2 a 5 termos que o paciente digitaria no Google e use-os no título e nos subtítulos.')
  end

  def seo_organic_rule(row)
    organic = row.dig(:sources, 'google_organico', :views).to_i
    return unless row[:views] >= MIN_VIEWS && organic.zero?

    build(row, 'seo_sem_organico', 'seo', 'Nenhuma visita veio do Google orgânico',
          "As #{row[:views]} visitas do período vieram de anúncio, link direto ou funil — nenhuma da busca gratuita.",
          'Revise título, descrição e palavras-chave e publique conteúdo que responda à dúvida do paciente; ' \
          'o resultado da busca gratuita leva semanas.')
  end

  # ── Search Console (o que acontece ANTES da visita) ───────────────────
  def search_console_insights
    gsc_pages = @gsc[:pages].select { |p| p[:page_id] && rows_by_id[p[:page_id]] }
    gsc_pages.flat_map { |p| [gsc_ctr_rule(p), gsc_near_top_rule(p)] } + gsc_orphan_terms
  end

  def rows_by_id
    @rows_by_id ||= @rows.select { |row| row[:page_id] }.index_by { |row| row[:page_id] }
  end

  # régua do CTR: as próprias páginas que já estão na 1ª página do Google
  # (posição ≤ 10); com menos de 2 delas, o domínio inteiro
  def avg_ctr # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @avg_ctr ||= begin
      top = @gsc[:pages].select { |p| p[:page_id] && p[:position].to_f.between?(0.1, 10) && p[:impressions] >= MIN_IMPRESSIONS }
      clicks, impressions = if top.size >= 2
                              [top.sum { |p| p[:clicks] }, top.sum { |p| p[:impressions] }]
                            else
                              [@gsc.dig(:totals, 'current', 'clicks').to_i, @gsc.dig(:totals, 'current', 'impressions').to_i]
                            end
      rate(clicks, impressions)
    end
  end

  def gsc_ctr_rule(gsc_page) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    row = rows_by_id[gsc_page[:page_id]]
    ctr = gsc_page[:ctr].to_f
    position = gsc_page[:position].to_f
    # só na 1ª página (posição ≤ 10): mais para baixo o CTR é baixo mesmo — quem cuida é o gsc_quase_topo
    return unless gsc_page[:impressions] >= MIN_IMPRESSIONS && position <= 10 && avg_ctr.positive? && ctr < avg_ctr * BELOW

    top = gsc_page[:terms].first(3).map { |t| "\"#{t[:query]}\" (#{t[:impressions]})" }.join(', ')
    title = row.dig(:seo, :title).presence || row[:title]
    gain = ((avg_ctr - ctr) / 100.0 * gsc_page[:impressions]).round
    build(row, 'gsc_ctr_baixo', 'seo', 'Aparece muito no Google e pouca gente clica',
          "#{gsc_page[:impressions]} aparições na busca e #{gsc_page[:clicks]} clique(s) (CTR #{pct(ctr)}, posição média " \
          "#{num(position)}). A média das suas páginas é #{pct(avg_ctr)}. Buscas que mais mostram a página: #{top.presence || '—'}.",
          "O título e a descrição são o \"anúncio\" gratuito no Google. Hoje o título é \"#{title}\". Reescreva " \
          'começando pelo termo mais buscado, diga o que a pessoa encontra (resposta, tempo, segurança) e ' \
          'termine a descrição com um convite. Depois de publicar, o Google leva de 1 a 3 semanas para mostrar o novo texto.',
          gain: gain.positive? ? "+#{gain} visita(s) do Google em 28 dias se chegasse na média" : nil, bonus: gain)
  end

  def gsc_near_top_rule(gsc_page) # rubocop:disable Metrics/AbcSize
    row = rows_by_id[gsc_page[:page_id]]
    position = gsc_page[:position].to_f
    return unless NEAR_TOP.cover?(position) && gsc_page[:impressions] >= MIN_IMPRESSIONS_NEAR

    near = gsc_page[:terms].select { |t| NEAR_TOP.cover?(t[:position].to_f) }.first(3)
                           .map { |t| "\"#{t[:query]}\" (posição #{num(t[:position])})" }.join(', ')
    build(row, 'gsc_quase_topo', 'seo', "Quase na 1ª página do Google (posição #{num(position)})",
          "Posição média #{num(position)} com #{gsc_page[:impressions]} aparições em 28 dias — da 8ª à 20ª posição quase " \
          "ninguém clica; subindo algumas casas, os cliques multiplicam. Buscas perto do topo: #{near.presence || '—'}.",
          'Reforce o conteúdo para essas buscas: um subtítulo que repete o termo e responde direto, uma pergunta ' \
          'no FAQ, um parágrafo com o que só a CEVICO mostra (exame, equipe, estrutura). E ponha links para esta ' \
          'página nas páginas irmãs ("Leia também") e no site cevico.com.br, com o termo no texto do link.',
          bonus: gsc_page[:impressions] / 10)
  end

  # termo que já traz clique e nenhuma página do sistema é "dona" do assunto
  def gsc_orphan_terms
    @gsc[:terms].filter_map do |term|
      next if term[:clicks] < MIN_TERM_CLICKS || term[:query].match?(BRAND)
      next if term_owner(term[:query], Array(term[:page_ids]))

      landing = term[:urls].first.to_s.sub(%r{\Ahttps?://}, '')
      build({ page_id: nil, title: 'Página nova', slug: '', emoji: '➕' }, "gsc_termo_sem_pagina:#{term[:query]}", 'seo',
            "\"#{term[:query]}\" traz clique e não tem página própria",
            "#{term[:clicks]} clique(s) e #{term[:impressions]} aparições em 28 dias (posição #{num(term[:position])}). " \
            "Nenhuma página do sistema é sobre esse assunto; hoje a busca cai em #{landing.presence || 'outro endereço do domínio'}.",
            'Vale uma página que responda exatamente a essa busca, com o termo no título, e o botão levando para a ' \
            'página de venda. Antes, confira se ela não disputaria a mesma busca com a /refrativa ou com outra ' \
            'página — nesse caso, vira uma seção da página que já existe.',
            bonus: term[:clicks])
    end
  end

  # a página "dona" de um termo: 2/3 das palavras do termo estão no endereço,
  # no título ou nas palavras-chave dela. Se a busca JÁ cai numa página do
  # sistema, basta metade (ex.: "catarata recuperação" na página de catarata
  # é reforço de conteúdo dela, não página nova)
  def term_owner(query, landing_ids = [])
    words = words_of(query)
    return true if words.empty?

    @rows.find do |row|
      next unless row[:page_id] && row[:status] == 'published'

      share = landing_ids.include?(row[:page_id]) ? 0.5 : 2 / 3.0
      text = page_words(row)
      words.count { |w| text.include?(w) } >= (words.size * share).ceil
    end
  end

  def page_words(row)
    @page_words ||= {}
    @page_words[row[:page_id]] ||= words_of([row[:slug].to_s.tr('-', ' '), row[:title], row.dig(:seo, :title),
                                             Array(row.dig(:seo, :keywords)).join(' ')].join(' ')).to_set
  end

  def words_of(text)
    I18n.transliterate(text.to_s.downcase).split(/[^a-z0-9]+/)
        .reject { |w| w.size < 3 || STOPWORDS.include?(w) }
        .map { |w| w.length > 4 ? w.delete_suffix('s') : w }
  end

  def num(value)
    value.to_f.round(1).to_s.delete_suffix('.0').tr('.', ',')
  end

  # ── a página campeã (oportunidade) ────────────────────────────────────
  def champion # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    best = @rows.select { |row| row[:page_id] && row[:views] >= MIN_VIEWS && row[:leads] >= 3 }
                .max_by { |row| rate(row[:leads], row[:views]) }
    return if best.nil? || @rows.count { |row| row[:page_id] && row[:views] >= MIN_VIEWS } < 2

    build(best, 'campea', 'oportunidade', 'Página campeã do período',
          "#{best[:leads]} lead(s) em #{best[:views]} visitas (#{pct(rate(best[:leads], best[:views]))}) — a melhor conversão entre as suas páginas.",
          'Use a estrutura dela (título, ordem das seções, convite) como modelo nas outras e mande mais visita para cá.')
  end

  # ── montagem ──────────────────────────────────────────────────────────
  def build(row, rule, level, title, evidence, suggestion, gain: nil, bonus: 0) # rubocop:disable Metrics/ParameterLists
    { key: "p#{row[:page_id]}:#{rule}", rule: rule.split(':').first, level: level, page_id: row[:page_id],
      page_title: row[:title], slug: row[:slug], emoji: row[:emoji], title: title, evidence: evidence,
      suggestion: suggestion, gain: gain, weight: LEVELS.fetch(level) + bonus.to_i.clamp(0, 99) }
  end

  def label(source)
    Cevico::TrafficSource::SOURCES[source] || source
  end

  def rate(part, total)
    total.to_i.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end

  def pct(value)
    "#{value.to_s.delete_suffix('.0').tr('.', ',')}%"
  end
end
