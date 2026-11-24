require 'rails_helper'

# 🏆 24/11: vitrine dos mais vendidos — a grife que mais vende sobe na ordem, sem passar por cima do rosto
RSpec.describe Otica::Vitrine do
  let(:account) { create(:account) }

  def armacao(name, shape, brand)
    Otica::Product.create!(account: account, kind: 'armacao', name: name, frame_shape: shape, brand: brand,
                           list_price: 300, quantity: 1)
  end

  it 'bônus pela raiz das vendas: Charmy no topo, grife fora do ranking zero', :aggregate_failures do
    charmy = armacao('Charmy', 'retangular', 'Charmy')
    detroit = armacao('Detroit', 'retangular', ' detroit ')
    hb = armacao('HB', 'retangular', 'HB')

    expect(described_class.bonus(charmy)).to eq(described_class::MAX_BONUS)
    expect(described_class.bonus(detroit)).to be_between(0.1, 0.2)
    expect(described_class.bonus(hb)).to eq(0.0)
    expect(described_class.campea?(detroit)).to be(true)
    expect(described_class.campea?(hb)).to be(false)
  end

  it 'no visagismo, entre formatos iguais a campeã vem antes; formato melhor ainda ganha de grife', :aggregate_failures do
    hb = armacao('HB retangular', 'retangular', 'HB')
    charmy = armacao('Charmy retangular', 'retangular', 'CHARMY')
    expect(Otica::Visagismo.recommend([hb, charmy], face_shape: 'redondo', limit: 2)).to eq([charmy, hb])

    # rosto redondo: retangular (1ª) × geométrica (4ª) = 0,9 de diferença > 0,6 de bônus da Charmy
    charmy_geo = armacao('Charmy geométrica', 'geometrica', 'CHARMY')
    expect(Otica::Visagismo.recommend([charmy_geo, hb], face_shape: 'redondo', limit: 1)).to eq([hb])
  end
end
