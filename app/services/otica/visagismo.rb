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
  def reason(face_shape, frame_shape)
    why = FRAME_WHY[frame_shape.to_s]
    return 'combina com o seu rosto' if why.nil?

    r = rule(face_shape)
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
  def match_level(face_shape, frame_shape)
    r = rule(face_shape)
    shape = frame_shape.to_s
    return 'exata' if r['recomendadas'].include?(shape)
    return 'foge' if r['evitar'].include?(shape)

    'aproximada'
  end

  # escolha HONESTA: tira as que fogem, prefere as exatas; devolve [escolhidas, nível geral, formatos ideais].
  # nível geral = 'exata' se a melhor é exata, 'aproximada' se só há aproximadas, 'nenhuma' se não sobrou nada.
  def honest_pick(products, face_shape:, preference: nil, limit: 2)
    r = rule(face_shape)
    pool = products.reject { |p| match_level(face_shape, p.frame_shape) == 'foge' }
    ideais = r['recomendadas'].map { |s| frame_label(s) }
    return [[], 'nenhuma', ideais] if pool.empty?

    exact = pool.select { |p| match_level(face_shape, p.frame_shape) == 'exata' }
    chosen = recommend(exact.presence || pool, face_shape: face_shape, preference: preference, limit: limit)
    # exatas de menos: completa com aproximadas (a cliente sempre compara 2)
    if exact.any? && chosen.size < limit
      chosen += recommend(pool - chosen, face_shape: face_shape, preference: preference, limit: limit - chosen.size)
    end
    [chosen, (exact.any? ? 'exata' : 'aproximada'), ideais]
  end

  def face_label(shape)
    FACE_SHAPES[shape.to_s] || shape.to_s
  end

  def frame_label(shape)
    FRAME_SHAPES[shape.to_s] || shape.to_s
  end

  def rule(face_shape)
    RULES[face_shape.to_s] || RULES['oval']
  end

  # frase curta para o agente / a equipe
  def explain(face_shape)
    r = rule(face_shape)
    "Rosto #{face_label(face_shape)}: #{r['porque']}. Combinam: #{r['recomendadas'].map { |s| frame_label(s) }.join(', ')}."
  end

  # ordena as armações do estoque para este rosto. products: Otica::Product
  # já filtrados (ativos, com foto, try_on, saldo). preference: texto livre da
  # cliente ("preta e fininha"). Devolve até `limit` produtos, os melhores primeiro.
  def recommend(products, face_shape:, preference: nil, limit: 3)
    r = rule(face_shape)
    words = preference_words(preference)
    scored = products.map { |p| [score(p, r, words), p] }
    # desempate estável: pontuação, depois saldo maior, depois id (nunca aleatório: a cliente pode pedir "outra")
    scored.sort_by { |score, p| [-score, -p.quantity.to_i, p.id.to_i] }.first(limit).map(&:last)
  end

  def score(product, rule, words) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    s = 0.0
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
    s += 0.2 if product.quantity.to_i > 1
    s
  end

  # "preta fininha" → ["preto", "preta", "black", "fina", "fino", …]
  def preference_words(preference)
    return [] if preference.blank?

    tokens = preference.to_s.downcase.scan(/[[:alpha:]]+/)
    tokens.flat_map { |t| PREFERENCE_WORDS[t] || (t.size >= 4 ? [t] : []) }.uniq
  end
end
