require 'rails_helper'

# 🪞 08/11: regras de visagismo (rosto → armação) e a ordenação do estoque
RSpec.describe Otica::Visagismo do
  let(:account) { create(:account) }

  def armacao(name, shape, color: '', quantity: 2, promo: nil)
    Otica::Product.create!(account: account, kind: 'armacao', name: name, frame_shape: shape, color: color,
                           list_price: 300, promo_price: promo, quantity: quantity)
  end

  it 'toda regra só cita formatos conhecidos e todo rosto tem regra', :aggregate_failures do
    expect(described_class::RULES.keys).to match_array(described_class::FACE_SHAPES.keys)
    described_class::RULES.each_value do |r|
      expect(r['recomendadas'] + r['evitar']).to all(satisfy { |s| described_class::FRAME_SHAPES.key?(s) })
      expect(r['recomendadas'] & r['evitar']).to be_empty
    end
  end

  it 'rosto redondo: armação com ângulos primeiro, a redonda por último; preferência de cor sobe a armação', :aggregate_failures do
    redonda = armacao('Redonda dourada', 'redonda', color: 'dourado')
    retangular = armacao('Retangular preta', 'retangular', color: 'preto')
    gatinho = armacao('Gatinho vinho', 'gatinho', color: 'vinho')
    sem_forma = armacao('Sem formato', '')

    ordem = described_class.recommend([redonda, retangular, gatinho, sem_forma], face_shape: 'redondo', limit: 4)
    expect(ordem).to eq([retangular, gatinho, sem_forma, redonda])

    com_cor = described_class.recommend([redonda, retangular, gatinho], face_shape: 'redondo', preference: 'quero uma dourada', limit: 3)
    expect(com_cor.first).to eq(retangular) # 3,0 pela regra contra 2,0 − 3,0 da redonda dourada
    expect(com_cor.last).to eq(redonda)

    expect(described_class.recommend([gatinho, retangular], face_shape: 'redondo', preference: 'gosto de vinho', limit: 1)).to eq([gatinho])
  end

  # 🔁 08/11 (noite): o agente só sugere o que combina; o que foge nunca vai; sem nada, diz a verdade
  it 'escolha honesta: exata > aproximada; a que foge fica de fora; sem nada devolve os formatos ideais', :aggregate_failures do
    redonda = armacao('Redonda', 'redonda')
    retangular = armacao('Retangular', 'retangular')
    aviador = armacao('Aviador', 'aviador')
    sem_forma = armacao('Sem formato', '')

    expect(described_class.match_level('redondo', 'retangular')).to eq('exata')
    expect(described_class.match_level('redondo', 'aviador')).to eq('aproximada')
    expect(described_class.match_level('redondo', 'redonda')).to eq('foge')
    expect(described_class.match_level('redondo', '')).to eq('aproximada')

    chosen, nivel, = described_class.honest_pick([redonda, retangular, aviador, sem_forma], face_shape: 'redondo', limit: 2)
    expect(nivel).to eq('exata')
    expect(chosen).to eq([retangular, aviador]) # 1 exata + completa com a melhor aproximada; a redonda (foge) nunca

    chosen, nivel, ideais = described_class.honest_pick([redonda, aviador], face_shape: 'redondo', limit: 2)
    expect(nivel).to eq('aproximada')
    expect(chosen).to eq([aviador])
    expect(ideais.first).to eq('retangular')

    chosen, nivel, ideais = described_class.honest_pick([redonda], face_shape: 'redondo', limit: 2)
    expect([chosen, nivel]).to eq([[], 'nenhuma'])
    expect(ideais).to include('gatinho')
  end

  it 'limita a quantidade, aceita rosto desconhecido como oval e explica em palavras simples', :aggregate_failures do
    a = armacao('A', 'retangular')
    b = armacao('B', 'gatinho')
    expect(described_class.recommend([a, b], face_shape: 'marciano', limit: 1).size).to eq(1)
    expect(described_class.explain('coracao')).to start_with('Rosto coração:').and include('aviador')
    expect(described_class.preference_words('Preta e fininha, de acetato')).to include('preto', 'fina', 'acetato')
    expect(described_class.preference_words('')).to eq([])
  end

  # 🚹🚺 22/11 (conversa #49: homem recebeu Jean Marcell feminina e depois a roxa e rosa)
  describe 'público (homem × mulher)' do
    def com_publico(name, shape, fit, color: '')
      armacao(name, shape, color: color).tap { |p| p.update!(frame_fit: fit) }
    end

    it 'homem nunca vê feminina, gatinho nem rosa/roxa; quadrada e retangular vêm primeiro', :aggregate_failures do
      fem = com_publico('Jean Marcell JM6105 cinza e verde', 'retangular', 'feminina', color: 'cinza e verde')
      roxa = com_publico('Unissex roxa e rosa', 'retangular', 'unissex', color: 'roxa e rosa')
      gatinho = com_publico('Gatinho preta', 'gatinho', 'unissex', color: 'preto')
      redonda = com_publico('Redonda masculina', 'redonda', 'masculina', color: 'preto')
      quadrada = com_publico('Bulget quadrada', 'quadrada', 'masculina', color: 'azul')
      retangular = com_publico('HB retangular', 'retangular', 'unissex', color: 'cinza')

      todas = [fem, roxa, gatinho, redonda, quadrada, retangular]
      expect(described_class.filter_gender(todas, 'masculino')).to contain_exactly(redonda, quadrada, retangular)

      chosen, nivel, = described_class.honest_pick(todas, face_shape: 'oval', gender: 'masculino', limit: 2)
      expect(chosen).to eq([quadrada, retangular])
      expect(nivel).to eq('exata')

      # 22/11 (tarde): moderno na frente, MAS combinando com o rosto: no rosto quadrado a quadrada foge
      expect(described_class.match_level('quadrado', 'quadrada', gender: 'masculino')).to eq('foge')
      expect(described_class.rule('quadrado', 'masculino')['recomendadas'].first).to eq('browline')
      expect(described_class.rule('oval', 'masculino')['recomendadas'].first(4)).to eq(%w[quadrada retangular geometrica browline])
      expect(described_class.match_level('quadrado', 'gatinho', gender: 'masculino')).to eq('foge')
      expect(described_class.match_level('quadrado', 'quadrada')).to eq('foge')
      expect(described_class.rule('oval', 'masculino')['recomendadas'].last(1)).to eq(['redonda'])
    end

    # 🌓 22/11: uma de cor escura e uma clara, pra saber do que a pessoa gosta mais
    it 'as 2 opções saem uma escura e uma clara quando o estoque deixa', :aggregate_failures do
      preta = com_publico('Quadrada preta', 'quadrada', 'masculina', color: 'preto')
      preta2 = com_publico('Quadrada grafite', 'quadrada', 'masculina', color: 'grafite')
      cristal = com_publico('Retangular cristal', 'retangular', 'unissex', color: 'transparente')

      chosen, = described_class.honest_pick([preta, preta2, cristal], face_shape: 'oval', gender: 'masculino', limit: 2)
      expect(chosen.map { |p| described_class.tone_of(p) }).to contain_exactly('escura', 'clara')
      expect(chosen.first.frame_shape).to eq('quadrada')
      expect(described_class.tone_of(com_publico('Havana', 'redonda', 'unissex', color: 'tartaruga clara'))).to eq('clara')
      expect(described_class.tone_of(com_publico('Sem cor', 'redonda', 'unissex', color: 'azul'))).to be_nil
    end

    it 'mulher não vê masculina; unissex vale pros dois; sem gênero nada muda', :aggregate_failures do
      fem = com_publico('Gatinho vinho', 'gatinho', 'feminina', color: 'vinho')
      masc = com_publico('Bulget BG8040M', 'retangular', 'masculina', color: 'azul')
      uni = com_publico('Unissex preta', 'retangular', 'unissex', color: 'preto')

      expect(described_class.filter_gender([fem, masc, uni], 'feminino')).to contain_exactly(fem, uni)
      expect(described_class.filter_gender([fem, masc, uni], nil)).to contain_exactly(fem, masc, uni)
      expect(described_class.gender_of('Masculino')).to eq('masculino')
      expect(described_class.gender_of('incerto')).to be_nil
    end

    it 'foto sem homem/mulher claro: só unissex neutra (sem gatinho nem rosa); sem nenhuma, volta tudo', :aggregate_failures do
      fem = com_publico('Gatinho vinho', 'gatinho', 'feminina', color: 'vinho')
      rosa = com_publico('Unissex rosa', 'retangular', 'unissex', color: 'rosa')
      uni = com_publico('Unissex preta', 'retangular', 'unissex', color: 'preto')
      expect(described_class.filter_neutral([fem, rosa, uni])).to eq([uni])
      expect(described_class.filter_neutral([fem, rosa])).to eq([fem, rosa])
    end
  end

  # 🔀 22/11: todo rosto oval recebia a MESMA sequência (desempate por saldo e id)
  it 'com a conversa como semente, a ordem entre armações empatadas varia de cliente pra cliente e é fixa na conversa', :aggregate_failures do
    pool = Array.new(8) { |i| armacao("Retangular #{i}", 'retangular') }
    firsts = (1..20).map { |conv| described_class.recommend(pool, face_shape: 'oval', limit: 1, seed: conv).first }
    expect(firsts.uniq.size).to be > 2
    primeira = described_class.recommend(pool, face_shape: 'oval', limit: 2, seed: 7)
    expect(described_class.recommend(pool.reverse, face_shape: 'oval', limit: 2, seed: 7)).to eq(primeira) # fixa na conversa
    # nunca passa um formato melhor na frente: a 1ª recomendada continua ganhando da última
    browline = armacao('Browline', 'browline')
    expect(described_class.recommend(pool + [browline], face_shape: 'oval', limit: 8, seed: 3)).not_to include(browline)
  end
end
