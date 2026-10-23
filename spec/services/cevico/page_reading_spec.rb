require 'rails_helper'

# 🩻 o mapa de leitura da página anexada: as MESMAS chaves que o beacon monta no navegador
RSpec.describe Cevico::PageReading do
  let(:html) do
    <<~HTML
      <nav><a href="https://wa.me/5511?text=Oi">WhatsApp</a><a href="/sobre">Sobre</a></nav>
      <h1>Cirurgia</h1>
      <h2>Isso acontece<br>com você?</h2>
      <a href="https://wa.me/5511" data-ev="cta_topo">Quero saber</a>
      <a href="https://wa.me/5511">Outro</a>
      <h2 id="fim-tit">Quer saber se<br>você pode fazer?</h2>
      <a href="/refrativa?de=guia">Ver a cirurgia</a>
      <a href="https://wa.me/5511" data-ev="Fora Do Padrão">Último</a>
      <h2>Ação & Coração: 1º passo</h2>
      <h2>Isso acontece com você?</h2>
      <h2> </h2>
    HTML
  end

  it 'lista os títulos (o <br> junta as palavras, como no navegador) e os botões de conversão, na ordem', :aggregate_failures do
    map = described_class.new(html).map

    expect(map['marcos']).to eq([
                                  { 'key' => 'isso-acontececom-voce', 'titulo' => 'Isso acontece com você?', 'secao' => '' },
                                  { 'key' => 'fim-tit', 'titulo' => 'Quer saber se você pode fazer?', 'secao' => '' },
                                  { 'key' => 'acao-coracao-1-passo', 'titulo' => 'Ação & Coração: 1º passo', 'secao' => '' },
                                  { 'key' => 'isso-acontece-com-voce', 'titulo' => 'Isso acontece com você?', 'secao' => '' }
                                ])
    expect(map['botoes'].pluck('key', 'marco')).to eq([%w[topo#1 topo], %w[cta_topo isso-acontececom-voce],
                                                       %w[isso-acontececom-voce#1 isso-acontececom-voce],
                                                       %w[fim-tit#1 fim-tit], %w[fim-tit#2 fim-tit]])
  end

  it 'guarda o id do bloco de cada título (ajuda a reconhecer investimento, dúvidas…)' do
    map = described_class.new('<section id="investimento"><div><h2>Transparente</h2></div></section><h2>Fim</h2>').map
    expect(map['marcos'].pluck('key', 'secao')).to eq([%w[transparente investimento], ['fim', '']])
  end

  it 'título repetido entra uma vez só' do
    map = described_class.new('<h2>Isso acontece<br>com você?</h2><h2>Isso acontececom você?</h2>').map
    expect(map['marcos'].pluck('key')).to eq(['isso-acontececom-voce'])
  end

  it 'slugify corta em 48 sem hífen no fim' do
    expect(described_class.slugify("#{'a' * 47} bcd")).to eq('a' * 47)
  end
end
