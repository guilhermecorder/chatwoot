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

  it 'limita a quantidade, aceita rosto desconhecido como oval e explica em palavras simples', :aggregate_failures do
    a = armacao('A', 'retangular')
    b = armacao('B', 'gatinho')
    expect(described_class.recommend([a, b], face_shape: 'marciano', limit: 1).size).to eq(1)
    expect(described_class.explain('coracao')).to start_with('Rosto coração:').and include('aviador')
    expect(described_class.preference_words('Preta e fininha, de acetato')).to include('preto', 'fina', 'acetato')
    expect(described_class.preference_words('')).to eq([])
  end
end
