require 'rails_helper'

# 🔌 Tabela de aumento de consumo aprovada pelo Guilherme (13/11): o que o cliente vai instalar → kWh por mês.
RSpec.describe Crm::KitQuote::Increase do
  def kwh(text)
    described_class.parse(text)[:itens].sum { |i| i['kwh'] }
  end

  it 'soma ar-condicionado pela quantidade e pelo tamanho (sem tamanho = o de 12 mil)', :aggregate_failures do
    expect(kwh('vai pôr 2 ar-condicionados de 12 mil')).to eq(180)
    expect(kwh('um ar 9000 btus')).to eq(70)
    expect(kwh('3 ar condicionado 24 mil')).to eq(450)
    expect(kwh('ar condicionado em 3 quartos')).to eq(270)
    expect(kwh('ar-condicionado no ano que vem')).to eq(90)
  end

  it 'carro elétrico (1.200 km por mês, ou os km que o cliente disser), piscina, chuveiro e geladeira', :aggregate_failures do
    expect(kwh('carro elétrico')).to eq(200)
    expect(kwh('carro elétrico, rodo 2.000 km')).to eq(345)
    expect(kwh('piscina')).to eq(100)
    expect(kwh('piscina aquecida')).to eq(400)
    expect(kwh('dois chuveiros + freezer')).to eq(200)
    expect(described_class.parse('2 ar-condicionados de 12 mil e um carro elétrico')[:itens].pluck('rotulo'))
      .to eq(['2 ar-condicionados (12.000 BTU)', 'carro elétrico'])
  end

  it 'o que a tabela não cobre fica com o Fernando', :aggregate_failures do
    expect(described_class.parse('sauna')[:desconhecido]).to eq('sauna')
    expect(described_class.parse('piscina com aquecedor de resistência')[:desconhecido]).to be_present
    expect(described_class.parse('ar condicionado no começo do ano')[:desconhecido]).to be_nil
  end
end
