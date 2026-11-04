# 🔥 MAPA DE CALOR de uma página anexada (23/10 — "em que seções houve maior
# desistência… aonde clicam errado… recomendar parâmetros de copywriting e
# testes"). A página é dividida em TRECHOS: a abertura (antes do 1º título) e
# um trecho por título <h2>. Para cada trecho, no período:
#
#   viram      visitas medidas que chegaram a ver o título dele
#   saida      parte de QUEM CHEGOU AO TRECHO que parou de ler nele (não viu o
#              próximo título) — é a "desistência" do trecho
#   perdidas   quantas visitas pararam nele (para ordenar onde dói mais)
#   botoes     toques nos botões que ficam no trecho
#   erros      toques errados no trecho: foto, título, algo com cara de botão,
#              texto, ou 3 toques seguidos no mesmo lugar
#   pontos     (mapa visual, 24/10) onde tocaram no celular: [{c, l, n, erro}] na
#              grade 10×10 do trecho — coluna da tela, linha da altura do trecho,
#              quantos, e erro = tocou onde não há nada para tocar. pontos_pc = no computador
#   segundos   (24/10) tempo médio com o trecho na tela, por visita que o viu —
#              contando só as visitas dos dias em que o tempo já era medido
#   status     boa / atencao / problema pelos PARÂMETROS abaixo (pouco = ainda
#              sem visitas suficientes para julgar)
#   recomendacoes + teste   o que mudar no texto e qual teste fazer, pelo tipo
#              do trecho (abertura, conteúdo, prova, investimento, dúvidas,
#              fecho) e pelo problema encontrado
#
# Os parâmetros são referências de partida para páginas de saúde em celular,
# calibradas depois com os números da própria CEVICO — não são promessa.
class Cevico::PageSections # rubocop:disable Metrics/ClassLength
  GROUPS = %w[scroll secoes botoes erros toques toques_pc tempo].freeze
  MIN_SEEN = 20 # abaixo disso o trecho fica "pouco": cedo para julgar
  # de quem chegou ao trecho, quantos param nele: [até aqui é boa, até aqui é atenção]
  EXIT_LIMITS = { 'abertura' => [0.30, 0.45], 'padrao' => [0.10, 0.25] }.freeze
  STRONG_MISS = %w[foto parece-botao repetido].freeze
  FLAGGED = %w[problema atencao].freeze
  MISS_LIMITS = [0.02, 0.05].freeze # toques errados "fortes" por quem viu: atenção / problema
  TEXT_MISS_LIMIT = 0.10
  WEAK_CTA = { min_seen: 50, rate: 0.01 }.freeze # trecho com botão: menos de 1% toca = convite fraco
  KINDS = {
    'investimento' => /investimento|custa|valor|preco|pagamento|parcel/,
    'duvidas' => /duvida|pergunta|faq/,
    'prova' => /depoimento|avalia|quem-ja|historia|pacientes|medicos|quem-cuida|equipe/
  }.freeze

  COPY = {
    'abertura' => ['O título repete as palavras da busca ou do anúncio (ex.: “cirurgia de miopia”): curto e com ponto final.',
                   'A primeira tela responde a pergunta em uma frase, para a pessoa confirmar que chegou ao lugar certo.',
                   'Um único convite visível sem rolar, com verbo + benefício.'],
    'conteudo' => ['Leia só os títulos em sequência: se a história não se conta sozinha, reescreva o título deste trecho.',
                   'Corte o texto pela metade: parágrafos de até 3 linhas e a frase-chave em negrito.',
                   'Comece pela dúvida de quem lê, não pela explicação técnica.'],
    'prova' => ['Depoimentos curtos que respondem o medo nº 1 (dor, segurança, recuperação), com nome e nota do Google.',
                'Mostre quem cuida: rosto, nome, CRM e RQE.'],
    'investimento' => ['Antes do valor, o que está incluso; depois, a parcela e o valor por dia.',
                       'Use “investimento”, nunca “preço” ou “custo”, com a comparação com a média de São Paulo.',
                       'Logo abaixo do valor, um convite para tirar dúvidas no WhatsApp.'],
    'duvidas' => ['Até 7 perguntas, na ordem dos medos reais, com respostas de 2 linhas.',
                  'A primeira pergunta é a que mais segura a decisão (ex.: “E se não der certo?”).'],
    'fecho' => ['Repita a promessa da abertura e mostre os 3 passos do que acontece depois do toque.',
                'Botão com verbo + benefício (“Quero saber se eu posso”) e “sem compromisso” embaixo.']
  }.freeze
  TEST = {
    'abertura' => 'Teste A/B do título no sistema (V1 × V2), sem mudar mais nada na página.',
    'conteudo' => 'Uma versão com este trecho pela metade, ou com ele depois do primeiro convite.',
    'prova' => 'Subir este trecho para logo depois da abertura.',
    'investimento' => 'Investimento antes × depois das dúvidas.',
    'duvidas' => 'Trocar a ordem das perguntas, começando pelo medo nº 1.',
    'fecho' => 'Dois textos para o botão final.'
  }.freeze
  MISS_COPY = {
    'foto' => 'As pessoas tocam na foto esperando que algo aconteça: faça a foto levar ao WhatsApp ou abrir maior, ' \
              'ou coloque um botão logo abaixo dela.',
    'parece-botao' => 'Algo com cara de botão (selo, etiqueta, destaque) não faz nada: vire botão de verdade ou tire a aparência de botão.',
    'repetido' => 'Toques repetidos no mesmo lugar indicam que algo não respondeu: confira no celular se o botão ou o carrossel ' \
                  'deste trecho funciona.',
    'texto' => 'Muitos toques no texto: letra pequena ou palavra que parece link. Aumente a letra e deixe os links com cara de link.',
    'titulo' => 'Tocam no título esperando abrir: se ele promete algo, coloque o link ou o botão logo embaixo.'
  }.freeze
  MISS_NAMES = { 'foto' => 'na foto', 'parece-botao' => 'em algo com cara de botão', 'repetido' => 'vários toques seguidos',
                 'texto' => 'no texto', 'titulo' => 'no título' }.freeze
  WEAK_CTA_COPY = 'Muita gente vê este trecho e quase ninguém toca no botão: troque o texto do botão (verbo + benefício) ' \
                  'e coloque uma frase de apoio embaixo.'.freeze
  MODEL_COPY = 'Este trecho segura a leitura e traz toques no botão: use como modelo para os outros.'.freeze

  def self.parameters
    { saida: EXIT_LIMITS, erros_fortes: MISS_LIMITS, erros_texto: TEXT_MISS_LIMIT, convite_fraco: WEAK_CTA, minimo: MIN_SEEN }
  end

  def initialize(page, since_date, until_date)
    @page = page
    @since = since_date.iso8601
    @until = until_date.iso8601
  end

  # soma do daily_stats no período: rolagem, títulos vistos, botões tocados, toques errados
  def stats
    @stats ||= begin
      out = GROUPS.index_with { Hash.new(0) }.merge('desde' => nil, 'viram_com_tempo' => Hash.new(0))
      period_days.each do |day, data|
        GROUPS.each { |group| add_counts(out[group], data[group]) }
        out['desde'] ||= day if data['scroll'].present?
        add_timed_views(out['viram_com_tempo'], data) if data['tempo'].present?
      end
      out
    end
  end

  # quem viu cada trecho nos dias em que o tempo já era medido (a abertura = visitas medidas)
  def add_timed_views(totals, data)
    totals[Cevico::PageReading::TOP] += (data['scroll'] || {}).values.sum(&:to_i)
    add_counts(totals, data['secoes'])
  end

  def add_counts(totals, counts)
    (counts || {}).each { |key, n| totals[key] += n.to_i }
  end

  # visitas medidas = um beacon por visita (a rolagem máxima dela, 0 = não rolou)
  def measured
    stats['scroll'].values.sum
  end

  def map
    @map ||= @page.custom_html.present? ? Cevico::PageReading.map_for(@page) : { 'marcos' => [], 'botoes' => [] }
  end

  def reached_end
    total = measured
    total.positive? ? stats['scroll']['100'].to_f / total : nil
  end

  def trechos
    @trechos ||= begin
      list = [{ 'key' => Cevico::PageReading::TOP, 'titulo' => 'Abertura (primeira tela)', 'viram' => measured }] +
             map['marcos'].map { |m| m.merge('viram' => stats['secoes'][m['key']]) }
      list.each_with_index.map { |trecho, i| evaluate(trecho, list[i + 1], i, list.size) }
    end
  end

  # o resumo para o painel de todas as páginas
  def resumo
    counted = trechos.reject { |t| t['status'] == 'pouco' }
    { medidas: measured, desde: stats['desde'],
      status: %w[problema atencao boa].index_with { |s| counted.count { |t| t['status'] == s } },
      erros: trechos.sum { |t| t['erros_total'] },
      trechos: counted.select { |t| FLAGGED.include?(t['status']) } }
  end

  private

  def period_days
    (@page.daily_stats || {}).sort.select { |day, _data| day.between?(@since, @until) }
  end

  def evaluate(trecho, following, index, size) # rubocop:disable Metrics/AbcSize
    kind = kind_of(trecho, index, size)
    seen = trecho['viram'].to_i
    # o último trecho não tem "próximo título": quem chega nele já leu a página
    lost = following ? [seen - following['viram'].to_i, 0].max : 0
    exit_rate = following && seen.positive? ? (lost.to_f / seen).round(4) : nil
    misses = misses_of(trecho['key'])
    taps = buttons_of(trecho['key'])
    out = trecho.merge('tipo' => kind, 'pct' => share(seen), 'saida' => exit_rate,
                       'perdidas' => lost, 'botoes' => taps,
                       'tem_botao' => map['botoes'].any? { |b| b['marco'] == trecho['key'] },
                       'erros' => misses, 'erros_total' => misses.values.sum,
                       'pontos' => taps_of(trecho['key'], 'toques'), 'pontos_pc' => taps_of(trecho['key'], 'toques_pc'),
                       'segundos' => seconds_of(trecho['key']))
    out.merge(judge(out))
  end

  def share(count)
    measured.positive? ? (count.to_f / measured).round(4) : nil
  end

  def kind_of(trecho, index, size)
    return 'abertura' if index.zero?
    return 'fecho' if index == size - 1

    # cada parte em separado: o slugify corta em 48 letras e o id do bloco ficaria de fora
    text = trecho.values_at('secao', 'key', 'titulo').map { |part| Cevico::PageReading.slugify(part) }.join(' ')
    KINDS.find { |_kind, rule| text.match?(rule) }&.first || 'conteudo'
  end

  def misses_of(key)
    Cevico::PageReading::MISS_TYPES.each_with_object({}) do |type, out|
      n = stats['erros']["#{key}~#{type}"]
      out[type] = n if n.positive?
    end
  end

  def seconds_of(key)
    total = stats['tempo'][key]
    seen = stats['viram_com_tempo'][key]
    seen.positive? && total.positive? ? (total.to_f / seen).round(1) : nil
  end

  def taps_of(key, group)
    prefix = "#{key}@"
    points = stats[group].filter_map { |k, n| tap_point(k, n) if k.start_with?(prefix) }
    points.sort_by { |p| [-p['n'], p['l'], p['c']] }
  end

  def tap_point(key, count)
    cell = key.delete_suffix('!')
    { 'c' => cell[-2].to_i, 'l' => cell[-1].to_i, 'n' => count, 'erro' => key.end_with?('!') }
  end

  def buttons_of(key)
    map['botoes'].select { |b| b['marco'] == key }.sum { |b| stats['botoes'][b['key']] }
  end

  # status + motivos + o que mudar + qual teste
  def judge(trecho) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    seen = trecho['viram'].to_i
    return { 'status' => 'pouco', 'motivos' => [], 'recomendacoes' => [], 'teste' => nil } if seen < MIN_SEEN

    levels = []
    reasons = []
    advice = []
    exit_status = exit_level(trecho)
    if exit_status
      levels << exit_status
      reasons << "De quem chegou aqui, #{pct(trecho['saida'])} parou de ler neste trecho " \
                 "(até #{pct(exit_limits(trecho)[0])} é bom; acima de #{pct(exit_limits(trecho)[1])} é problema)."
      advice.concat(COPY[trecho['tipo']] || COPY['conteudo'])
    end
    trecho['erros'].each do |type, n|
      rate = n.to_f / seen
      level = miss_level(type, rate)
      next if level.nil?

      levels << level
      reasons << "#{pct(rate)} de quem viu este trecho fez um toque errado (#{MISS_NAMES[type]})."
      advice << MISS_COPY[type]
    end
    if trecho['tem_botao'] && seen >= WEAK_CTA[:min_seen] && trecho['botoes'].to_f / seen < WEAK_CTA[:rate]
      levels << 'atencao'
      reasons << "#{seen} visitas viram este trecho e #{trecho['botoes']} tocaram no botão dele."
      advice << WEAK_CTA_COPY
    end
    status = %w[problema atencao].find { |level| levels.include?(level) } || 'boa'
    advice << MODEL_COPY if status == 'boa' && trecho['botoes'].to_f / seen >= 0.03
    { 'status' => status, 'motivos' => reasons, 'recomendacoes' => advice.uniq, 'teste' => test_for(trecho, status, exit_status) }
  end

  def test_for(trecho, status, exit_status)
    return nil if status == 'boa'
    return TEST[trecho['tipo']] if exit_status

    'Uma mudança por vez neste trecho, comparando o antes e o depois.'
  end

  def exit_limits(trecho)
    EXIT_LIMITS[trecho['tipo'] == 'abertura' ? 'abertura' : 'padrao']
  end

  def exit_level(trecho)
    rate = trecho['saida']
    return nil if rate.nil?

    good, bad = exit_limits(trecho)
    return 'problema' if rate > bad

    'atencao' if rate > good
  end

  def miss_level(type, rate)
    if STRONG_MISS.include?(type)
      return 'problema' if rate >= MISS_LIMITS[1]

      'atencao' if rate >= MISS_LIMITS[0]
    elsif rate >= TEXT_MISS_LIMIT
      'atencao'
    end
  end

  def pct(value)
    number = value.to_f * 100
    "#{number < 10 ? format('%.1f', number).tr('.', ',') : number.round}%"
  end
end
