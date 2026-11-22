# 🪞 VISAGISMO (08/11/2026): as regras de "qual armação combina com qual rosto",
# escritas uma vez, usadas pelo agente do WhatsApp (ferramenta
# experimentar_armacoes), pela tela de Produtos (prova virtual de teste) e
# pela leitura da foto (Otica::FaceReading).
#
# A regra clássica é CONTRASTE: o formato da armação compensa o formato do
# rosto. Rosto redondo pede armação com ângulos (retangular, quadrada,
# gatinho); rosto quadrado pede curvas (redonda, oval, aviador); rosto oval
# aceita quase tudo; rosto coração (testa larga, queixo fino) pede armação
# mais leve embaixo (aviador, redonda, sem aro); rosto alongado pede armação
# alta/larga que "encurte" o rosto; diamante (maçãs do rosto largas) pede
# gatinho, oval e sem aro; triangular (queixo mais largo que a testa) pede
# armação com peso em cima (browline, gatinho, geométrica).
#
# Nada aqui é lei: a lista de recomendadas ordena o estoque; a preferência da
# cliente (cor, estilo) e o saldo entram no desempate. Quem bate o martelo é a
# cliente, na loja, com a armação no rosto.
module Otica::Visagismo
  module_function

  FACE_SHAPES = {
    'oval' => 'oval',
    'redondo' => 'redondo',
    'quadrado' => 'quadrado',
    'coracao' => 'coração',
    'alongado' => 'alongado',
    'diamante' => 'diamante',
    'triangular' => 'triangular'
  }.freeze

  FRAME_SHAPES = {
    'retangular' => 'retangular',
    'quadrada' => 'quadrada',
    'redonda' => 'redonda',
    'oval' => 'oval',
    'gatinho' => 'gatinho',
    'aviador' => 'aviador',
    'browline' => 'browline (aro em cima)',
    'geometrica' => 'geométrica',
    'sem_aro' => 'sem aro / três peças',
    'borboleta' => 'borboleta (grande)'
  }.freeze

  FRAME_FITS = { 'feminina' => 'feminina', 'masculina' => 'masculina', 'unissex' => 'unissex' }.freeze

  # rosto → armações que combinam (em ordem), as que fogem, e o porquê em
  # palavras simples (o agente pode usar a frase com a cliente)
  RULES = {
    'oval' => {
      'recomendadas' => %w[retangular gatinho aviador quadrada geometrica redonda browline],
      'evitar' => %w[borboleta],
      'porque' => 'rosto oval é o mais equilibrado: quase todo formato combina; só armação grande demais esconde o rosto'
    },
    'redondo' => {
      'recomendadas' => %w[retangular quadrada gatinho geometrica browline],
      'evitar' => %w[redonda oval],
      'porque' => 'rosto redondo ganha definição com armação de ângulos (retangular, quadrada, gatinho); a redonda arredonda ainda mais'
    },
    'quadrado' => {
      'recomendadas' => %w[redonda oval aviador gatinho sem_aro],
      'evitar' => %w[quadrada retangular geometrica],
      'porque' => 'rosto quadrado (maxilar marcado) suaviza com armação de curvas (redonda, oval, aviador); a quadrada endurece o traço'
    },
    'coracao' => {
      'recomendadas' => %w[aviador redonda oval sem_aro retangular],
      'evitar' => %w[gatinho browline borboleta],
      'porque' => 'rosto coração (testa mais larga, queixo fino) equilibra com armação mais leve e larga embaixo (aviador, redonda, sem aro); peso em cima alarga a testa'
    },
    'alongado' => {
      'recomendadas' => %w[quadrada borboleta geometrica aviador redonda],
      'evitar' => %w[retangular sem_aro],
      'porque' => 'rosto alongado pede armação alta e larga (quadrada, grande, aviador), que encurta o rosto; a retangular fina alonga mais'
    },
    'diamante' => {
      'recomendadas' => %w[gatinho oval sem_aro browline redonda],
      'evitar' => %w[retangular quadrada],
      'porque' => 'rosto diamante (maçãs do rosto largas, testa e queixo finos) fica bem com gatinho, oval e sem aro, que suavizam as maçãs'
    },
    'triangular' => {
      'recomendadas' => %w[browline gatinho geometrica aviador retangular],
      'evitar' => %w[sem_aro],
      'porque' => 'rosto triangular (queixo mais largo que a testa) equilibra com armação de peso em cima (browline, gatinho); sem aro some no rosto'
    }
  }.freeze

  # cores e materiais que a cliente costuma pedir ("quero preta", "dourada",
  # "de acetato") — batem com color/material do cadastro
  PREFERENCE_WORDS = {
    'preta' => %w[preto preta black], 'preto' => %w[preto preta black],
    'dourada' => %w[dourado dourada gold ouro], 'dourado' => %w[dourado dourada gold ouro],
    'prata' => %w[prata prateado prateada silver], 'prateada' => %w[prata prateado prateada silver],
    'tartaruga' => %w[tartaruga havana havana tortoise], 'havana' => %w[tartaruga havana havana tortoise],
    'vermelha' => %w[vermelho vermelha red vinho bordo bordô], 'vinho' => %w[vinho bordo bordô vermelho],
    'azul' => %w[azul blue], 'rosa' => %w[rosa pink nude], 'transparente' => %w[transparente cristal clear],
    'marrom' => %w[marrom brown], 'verde' => %w[verde green],
    'acetato' => %w[acetato], 'metal' => %w[metal metálica metalica titânio titanio],
    'fina' => %w[fina fino slim leve], 'fininha' => %w[fina fino slim leve], 'fininho' => %w[fina fino slim leve],
    'leve' => %w[leve fina titânio titanio],
    'grande' => %w[grande oversized borboleta], 'pequena' => %w[pequena pequeno slim]
  }.freeze

  # 🪞 08/11: o "por quê" de cada formato de armação, em 1 frase simples (vai na legenda da foto)
  FRAME_WHY = {
    'retangular' => 'dá definição e alonga o olhar',
    'quadrada' => 'traz estrutura e deixa o rosto mais marcado',
    'redonda' => 'suaviza os traços e deixa o rosto mais leve',
    'oval' => 'acompanha as curvas do rosto sem pesar',
    'gatinho' => 'levanta o olhar e valoriza as maçãs do rosto',
    'aviador' => 'equilibra a testa com o queixo',
    'geometrica' => 'dá personalidade sem pesar no rosto',
    'browline' => 'destaca a parte de cima do rosto e os olhos',
    'borboleta' => 'dá presença e cobre bem',
    'sem_aro' => 'fica leve e quase some, deixando o rosto em evidência'
  }.freeze

  # "No seu rosto oval, a retangular dá definição e alonga o olhar." (sem termo técnico)
  def reason(face_shape, frame_shape, gender: nil)
    why = FRAME_WHY[frame_shape.to_s]
    return 'combina com o seu rosto' if why.nil?

    r = rule(face_shape, gender)
    if r['recomendadas'].include?(frame_shape.to_s)
      "no seu rosto #{face_label(face_shape)}, a #{frame_label(frame_shape)} #{why}"
    else
      "a #{frame_label(frame_shape)} #{why}"
    end
  end

  # 🔁 08/11 (noite, pedido do Guilherme): o agente só mostra o que EXISTE no estoque e
  # diz a verdade sobre o quanto combina. Nível da combinação rosto × armação:
  #   exata      = formato está nas recomendadas pro rosto
  #   aproximada = não é das recomendadas, mas também não foge (ou formato não cadastrado)
  #   foge       = está em "evitar": nunca vai pra cliente como sugestão
  LEVELS = %w[exata aproximada foge].freeze
  def match_level(face_shape, frame_shape, gender: nil)
    r = rule(face_shape, gender)
    shape = frame_shape.to_s
    return 'exata' if r['recomendadas'].include?(shape)
    return 'foge' if r['evitar'].include?(shape)

    'aproximada'
  end

  # escolha HONESTA: tira as que fogem, prefere as exatas; devolve [escolhidas, nível geral, formatos ideais].
  # nível geral = 'exata' se a melhor é exata, 'aproximada' se só há aproximadas, 'nenhuma' se não sobrou nada.
  # 🚹🚺 22/11: gender filtra ANTES (feminina nunca vai pra homem, masculina nunca pra mulher)
  def honest_pick(products, face_shape:, preference: nil, limit: 2, gender: nil, seed: nil) # rubocop:disable Metrics/ParameterLists
    r = rule(face_shape, gender)
    pool = filter_gender(products, gender).reject { |p| match_level(face_shape, p.frame_shape, gender: gender) == 'foge' }
    ideais = r['recomendadas'].map { |s| frame_label(s) }
    return [[], 'nenhuma', ideais] if pool.empty?

    exact = pool.select { |p| match_level(face_shape, p.frame_shape, gender: gender) == 'exata' }
    opts = { face_shape: face_shape, preference: preference, limit: pool.size, gender: gender, seed: seed }
    ranked_exact = recommend(exact, **opts)
    ranked_pool = recommend(pool, **opts)
    # 🌓 22/11: uma de cor ESCURA e uma de cor CLARA (a pessoa mostra do que gosta mais)
    chosen = contrast_pick(ranked_exact.presence || ranked_pool, ranked_pool, limit)
    [chosen, (exact.any? ? 'exata' : 'aproximada'), ideais]
  end

  # 🌓 22/11 (Guilherme: "oferecer tanto uma cor clara quanto uma cor escura, pra saber o que a pessoa gosta
  # mais"): a 1ª é a melhor da lista; a 2ª é a melhor de TOM OPOSTO (primeiro entre as do formato ideal,
  # depois entre as que também servem); sem nenhuma de tom oposto, a 2ª melhor. Completa até `limit`.
  def contrast_pick(ranked, fallback, limit) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return [] if ranked.empty?

    first = ranked.first
    chosen = [first]
    if limit >= 2
      opposite = ->(p) { p != first && contrast?(tone_of(first), tone_of(p)) }
      second = ranked.find(&opposite) || fallback.find(&opposite)
      chosen << second if second
    end
    (ranked + fallback).each do |p|
      break if chosen.size >= limit

      chosen << p unless chosen.include?(p)
    end
    chosen.first(limit)
  end

  # a 1ª sem tom conhecido: não força contraste (segue a ordem do visagismo)
  def contrast?(tone_a, tone_b)
    tone_a.present? && tone_b.present? && tone_b != tone_a
  end

  # 🌓 tom da armação pela cor do cadastro: 'escura', 'clara' ou nil (não dá pra saber)
  DARK_WORDS = %w[preto preta black grafite chumbo gunmetal escuro escura marinho navy tartaruga havana marrom brown
                  vinho bordo bordô café cafe chocolate onix ônix].freeze
  LIGHT_WORDS = %w[transparente cristal clear nude bege dourado dourada gold ouro prata prateado prateada silver rose rosé
                   champagne mel branco branca claro clara rosa lilás lilas acqua translucido translúcido areia].freeze
  def tone_of(product)
    text = [product.color, product.name].join(' ').downcase
    words = text.scan(/[[:alpha:]]+/)
    return 'clara' if words.intersect?(LIGHT_WORDS)
    return 'escura' if words.intersect?(DARK_WORDS)

    nil
  end

  # 🚹🚺 22/11/2026 (Guilherme, print da conversa #49: homem recebeu Jean Marcell feminina e depois a
  # ROXA E ROSA — "achei meio feminino"): homem vê armação masculina, mulher vê feminina; unissex vale
  # pros dois. Gosto masculino: principalmente QUADRADA/RETANGULAR; redonda às vezes; gatinho,
  # borboleta e rosa/roxo/lilás NUNCA. Gênero vem da leitura da foto (FaceReading 'genero') ou do agente.
  GENDERS = %w[masculino feminino].freeze
  GENDER_FIT = { 'masculino' => 'masculina', 'feminino' => 'feminina' }.freeze
  MALE_NEVER_SHAPES = %w[gatinho borboleta].freeze
  MALE_NEVER_COLORS = %w[rosa rose rosé pink roxo roxa lilás lilas lavanda nude magenta fúcsia fucsia].freeze
  MALE_TOP_SHAPES = %w[quadrada retangular].freeze
  # 22/11 (tarde): os "modernos" que o homem prefere, na ordem
  MALE_MODERN_SHAPES = %w[quadrada retangular geometrica browline].freeze
  MALE_RARE_SHAPES = %w[redonda oval].freeze

  def gender_of(value)
    v = value.to_s.strip.downcase
    return 'masculino' if v.start_with?('masc', 'homem', 'home')
    return 'feminino' if v.start_with?('fem', 'mulher')

    nil
  end

  # serve pra esse público? feminina nunca vai pra homem (e masculina nunca pra mulher); pro homem,
  # além disso, gatinho/borboleta e cor rosa/roxa ficam de fora mesmo se o cadastro disser unissex
  def fits_gender?(product, gender)
    g = gender_of(gender)
    return true if g.nil?

    fit = product.frame_fit.to_s
    return fit != 'masculina' if g == 'feminino'
    return false if fit == 'feminina' || MALE_NEVER_SHAPES.include?(product.frame_shape.to_s)

    color = [product.color, product.name].join(' ').downcase
    MALE_NEVER_COLORS.none? { |c| color.match?(/(?<![[:alpha:]])#{Regexp.escape(c)}(?![[:alpha:]])/) }
  end

  def filter_gender(products, gender)
    products.select { |p| fits_gender?(p, gender) }
  end

  # 🚻 22/11: a foto não deixou claro se é homem ou mulher → só unissex "neutra" (sem gatinho, borboleta
  # nem rosa/roxo), que não erra pra nenhum dos dois. Sem nenhuma assim, volta tudo.
  def filter_neutral(products)
    safe = products.select { |p| p.frame_fit.to_s == 'unissex' && fits_gender?(p, 'masculino') }
    safe.presence || products
  end

  def face_label(shape)
    FACE_SHAPES[shape.to_s] || shape.to_s
  end

  def frame_label(shape)
    FRAME_SHAPES[shape.to_s] || shape.to_s
  end

  # 🚹 22/11: pro HOMEM a regra do rosto ganha o gosto masculino: os MODERNOS (quadrada, retangular,
  # geométrica, browline) na frente, redonda/oval só no fim (às vezes), gatinho e borboleta nunca.
  # 22/11 (tarde, Guilherme: "priorizar quadrados e modernos, mas que combine com o formato do
  # rosto"): moderno que FOGE do rosto (ex.: quadrada no rosto quadrado) não entra na frente.
  def rule(face_shape, gender = nil)
    base = RULES[face_shape.to_s] || RULES['oval']
    return base unless gender_of(gender) == 'masculino'

    modern = MALE_MODERN_SHAPES - base['evitar']
    rest = base['recomendadas'] - MALE_NEVER_SHAPES - MALE_MODERN_SHAPES
    rare = rest & MALE_RARE_SHAPES
    { 'recomendadas' => modern + (rest - rare) + rare,
      'evitar' => (base['evitar'] + MALE_NEVER_SHAPES).uniq,
      'porque' => base['porque'] }
  end

  # frase curta para o agente / a equipe
  def explain(face_shape, gender = nil)
    r = rule(face_shape, gender)
    "Rosto #{face_label(face_shape)}: #{r['porque']}. Combinam: #{r['recomendadas'].map { |s| frame_label(s) }.join(', ')}."
  end

  # ordena as armações do estoque para este rosto. products: Otica::Product
  # já filtrados (ativos, com foto, try_on, saldo). preference: texto livre da
  # cliente ("preta e fininha"). Devolve até `limit` produtos, os melhores primeiro.
  def recommend(products, face_shape:, preference: nil, limit: 3, gender: nil, seed: nil) # rubocop:disable Metrics/ParameterLists
    r = rule(face_shape, gender)
    words = preference_words(preference)
    g = gender_of(gender)
    scored = filter_gender(products, g).map { |p| [score(p, r, words, g) + shuffle_bonus(seed, p), p] }
    # desempate: pontuação, depois saldo maior, depois id. 🔀 22/11: com `seed` (a conversa), cada cliente ganha
    # uma ordem própria entre armações de pontuação parecida (antes todo rosto oval via a MESMA HB Switch);
    # a ordem é fixa dentro da conversa, então "outra" continua trazendo novas.
    scored.sort_by { |score, p| [-score, -p.quantity.to_i, p.id.to_i] }.first(limit).map(&:last)
  end

  # 0 a 0,29: menor que o degrau entre duas posições da regra (0,3), então nunca passa um formato melhor na frente
  def shuffle_bonus(seed, product)
    return 0.0 if seed.nil?

    (Zlib.crc32("#{seed}-#{product.id}") % 30) / 100.0
  end

  def score(product, rule, words, gender = nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    s = 0.0
    # 🚹🚺 22/11: a armação do público dele/dela vem antes da unissex
    s += 1.0 if gender && product.frame_fit.to_s == GENDER_FIT[gender]
    shape = product.frame_shape.to_s
    if (pos = rule['recomendadas'].index(shape))
      s += 3.0 - (pos * 0.3) # a 1ª recomendada vale mais que a 5ª
    elsif rule['evitar'].include?(shape)
      s -= 3.0
    elsif shape.blank?
      s -= 0.5 # sem formato cadastrado: entra, mas por último
    end
    haystack = [product.color, product.brand, product.line, product.model, product.name, product.visagismo_notes,
                product.lens_material].join(' ').downcase
    words.each { |w| s += 2.0 if haystack.include?(w) }
    s += 0.5 if product.promo_active?
    s
  end

  # "preta fininha" → ["preto", "preta", "black", "fina", "fino", …]
  def preference_words(preference)
    return [] if preference.blank?

    tokens = preference.to_s.downcase.scan(/[[:alpha:]]+/)
    tokens.flat_map { |t| PREFERENCE_WORDS[t] || (t.size >= 4 ? [t] : []) }.uniq
  end
end
