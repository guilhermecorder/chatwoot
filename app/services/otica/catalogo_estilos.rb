# 📖 CATÁLOGO DE ESTILOS (22/11/2026, pedido do Guilherme): quando a prova virtual
# erra DUAS vezes (a pessoa não gostou de nenhuma das opções), o sistema para de
# chutar e manda o catálogo dos principais tipos de óculos — um para homem (com o
# Roberto, avatar da loja) e um para mulher — cada estilo com um CÓDIGO (M1…M8,
# F1…F8). A pessoa responde o código e a próxima prova sai SÓ com armações do
# estoque daquele estilo, uma de cor escura e uma de cor clara.
#
# Não precisa ser perfeito: é para entender o gosto dela e chegar perto. Quem
# bate o martelo é ela, na loja, com a armação no rosto (e o exame de vista).
#
# formatos  = frame_shape do cadastro (Otica::Product) que contam como esse estilo
# preferencia = palavras que puxam o desempate (Otica::Visagismo.preference_words)
# As imagens ficam em public/otica/catalogo/ (masculino.jpg, feminino.jpg).
module Otica::CatalogoEstilos
  module_function

  STYLES = {
    'M1' => { publico: 'masculino', nome: 'Quadrado clássico', descricao: 'acetato encorpado, marcante',
              formatos: %w[quadrada], preferencia: 'acetato' },
    'M2' => { publico: 'masculino', nome: 'Retangular fino', descricao: 'metal fino, discreto e executivo',
              formatos: %w[retangular], preferencia: 'metal fina' },
    'M3' => { publico: 'masculino', nome: 'Aro em cima (browline)', descricao: 'acetato em cima, metal embaixo',
              formatos: %w[browline], preferencia: '' },
    'M4' => { publico: 'masculino', nome: 'Geométrico moderno', descricao: 'sextavado, metal fino',
              formatos: %w[geometrica], preferencia: 'metal' },
    'M5' => { publico: 'masculino', nome: 'Quadrado transparente', descricao: 'acetato cristal, leve e moderno',
              formatos: %w[quadrada retangular], preferencia: 'transparente' },
    'M6' => { publico: 'masculino', nome: 'Aviador', descricao: 'metal com ponte dupla',
              formatos: %w[aviador], preferencia: 'metal' },
    'M7' => { publico: 'masculino', nome: 'Redondo', descricao: 'acetato tartaruga, estilo vintage',
              formatos: %w[redonda oval], preferencia: 'tartaruga' },
    'M8' => { publico: 'masculino', nome: 'Sem aro', descricao: 'leve, quase some no rosto',
              formatos: %w[sem_aro], preferencia: 'leve' },
    'F1' => { publico: 'feminino', nome: 'Gatinho', descricao: 'pontas levantadas, elegante',
              formatos: %w[gatinho], preferencia: '' },
    'F2' => { publico: 'feminino', nome: 'Redondo delicado', descricao: 'metal fino dourado',
              formatos: %w[redonda], preferencia: 'metal dourada' },
    'F3' => { publico: 'feminino', nome: 'Oval suave', descricao: 'acetato em cor suave',
              formatos: %w[oval], preferencia: 'nude' },
    'F4' => { publico: 'feminino', nome: 'Quadrado grande', descricao: 'maior, cheio de estilo',
              formatos: %w[quadrada borboleta], preferencia: 'grande tartaruga' },
    'F5' => { publico: 'feminino', nome: 'Retangular fino', descricao: 'discreto e sofisticado',
              formatos: %w[retangular], preferencia: 'fina' },
    'F6' => { publico: 'feminino', nome: 'Borboleta', descricao: 'grande, com as pontas para cima',
              formatos: %w[borboleta gatinho], preferencia: 'grande' },
    'F7' => { publico: 'feminino', nome: 'Geométrico', descricao: 'sextavado, metal fino',
              formatos: %w[geometrica], preferencia: 'metal dourada' },
    'F8' => { publico: 'feminino', nome: 'Transparente', descricao: 'acetato cristal, leve e moderno',
              formatos: %w[quadrada redonda oval retangular], preferencia: 'transparente' }
  }.freeze

  IMAGES = { 'masculino' => 'masculino.jpg', 'feminino' => 'feminino.jpg' }.freeze
  DIR = Rails.public_path.join('otica/catalogo')

  # "m3", "M 3", "o 3", "3" (com o público) → "M3"; nil se não reconhece
  def normalize(code, gender = nil)
    raw = code.to_s.upcase.gsub(/[^A-Z0-9]/, '')
    return raw if STYLES.key?(raw)

    digits = raw[/\d+/]
    return nil if digits.nil?

    prefix = Otica::Visagismo.gender_of(gender) == 'feminino' ? 'F' : 'M'
    prefix = raw[0] if %w[M F].include?(raw[0])
    key = "#{prefix}#{digits.to_i}"
    STYLES.key?(key) ? key : nil
  end

  def style(code)
    STYLES[code.to_s]
  end

  def for_gender(gender)
    g = Otica::Visagismo.gender_of(gender)
    STYLES.select { |_code, s| g.nil? || s[:publico] == g }
  end

  def image_path(gender)
    file = IMAGES[Otica::Visagismo.gender_of(gender) || 'feminino']
    DIR.join(file)
  end

  # "M1 Quadrado clássico · M2 Retangular fino · …" (legenda da imagem e resumo para o agente)
  def legend(gender)
    for_gender(gender).map { |code, s| "#{code} #{s[:nome]}" }.join(' · ')
  end

  # estoque do estilo: armações cujo formato está no estilo (o público já vem filtrado de fora)
  def products_for(code, products)
    s = style(code)
    return [] if s.nil?

    products.select { |p| s[:formatos].include?(p.frame_shape.to_s) }
  end
end
