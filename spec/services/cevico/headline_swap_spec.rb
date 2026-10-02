require 'rails_helper'

# 🧪 item 306: teste A/B em página HTML anexada — a variação troca só o <h1>
RSpec.describe Cevico::HeadlineSwap do
  let(:html) do
    '<html><body><section class="hero"><span class="eyebrow">Refrativa</span>' \
      '<h1>Enxergar bem,<br><span>o novo normal.</span></h1><p class="lead">Texto</p></section>' \
      '<h2>Outra</h2></body></html>'
  end

  it 'sem título devolve o HTML intocado' do
    expect(described_class.call(html, nil)).to eq(html)
    expect(described_class.call(html, '  ')).to eq(html)
  end

  it 'troca só o conteúdo do h1 e deixa o resto da página igual', :aggregate_failures do
    out = described_class.call(html, 'Enxergar sem óculos')
    expect(out).to include('<h1>Enxergar sem óculos</h1>')
    expect(out).not_to include('o novo normal')
    expect(out).to include('<span class="eyebrow">Refrativa</span>', '<p class="lead">Texto</p>', '<h2>Outra</h2>')
  end

  it '*asteriscos* viram o trecho de destaque' do
    out = described_class.call(html, 'Descubra se você pode *deixar os óculos para trás.*')
    expect(out).to include('Descubra se você pode <span>deixar os óculos para trás.</span></h1>')
  end

  it 'headline comprida ganha letra menor; curta mantém o tamanho da página', :aggregate_failures do
    curta = described_class.call(html, 'Enxergar bem, o novo normal.')
    media = described_class.call(html, 'Descubra se você pode deixar os óculos para trás.')
    longa = described_class.call(html, 'Enxergar sem depender dos óculos pode estar mais perto do que você imagina')
    expect(curta).to include('<h1>Enxergar bem')
    expect(media).to include("<h1 style=\"#{described_class::SIZE_MEDIUM}\">")
    expect(longa).to include("<h1 style=\"#{described_class::SIZE_LONG}\">")
  end

  it 'texto do admin nunca vira HTML' do
    out = described_class.call(html, 'Oi <script>alert(1)</script> & tchau')
    expect(out).to include('Oi &lt;script&gt;alert(1)&lt;/script&gt; &amp; tchau')
  end

  it 'página sem h1 fica como está' do
    plain = '<html><body><h2>Sem headline</h2></body></html>'
    expect(described_class.call(plain, 'Nova')).to eq(plain)
  end
end
