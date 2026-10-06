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
#   campea               a página que mais converte (modelo para as outras)
#
# A régua de comparação é a MÉDIA DAS PRÓPRIAS PÁGINAS no período — nunca um
# número de mercado inventado. E só fala quando há volume mínimo (abaixo disso
# é ruído): MIN_VIEWS visitas, MIN_CLICKS cliques, MIN_LEADS leads.
class Cevico::PageInsights
  MIN_VIEWS = 30
  MIN_CLICKS = 8
  MIN_LEADS = 5
  BELOW = 0.6 # "bem abaixo da média" = menos de 60% dela
  PAID = %w[google_ads meta_ads outros_ads].freeze
  LEVELS = { 'alerta' => 300, 'atencao' => 200, 'oportunidade' => 100, 'seo' => 50 }.freeze
  TITLE_MAX = 60
  DESCRIPTION_RANGE = (70..160)

  def initialize(rows:, totals:)
    @rows = rows
    @totals = totals
  end

  def call
    list = @rows.flat_map { |row| page_insights(row) }
    list << champion
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
