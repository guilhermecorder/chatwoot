require 'rails_helper'

# DRE projetado da LIFE. Regras ditas pelo Guilherme em 11/11/2026: sem comissão, sem seguro,
# imposto de 10%, adequação pela tabela, padrão de 25% de lucro. Os números do caso da Adriana
# são os mesmos do gerador dos PDFs (LIFE/orcamento/dre/gerar_dre.py).
RSpec.describe Crm::KitQuote::Dre do
  let(:bluesun) { [{ 'fornecedor' => 'Bluesun', 'valor' => 7178.80 }] }

  describe 'tabela de adequação' do
    it 'devolve o valor de cada faixa do micro inversor' do
      expected = { 4 => 550, 8 => 550, 9 => 700, 12 => 700, 13 => 950, 16 => 950, 17 => 1000, 20 => 1000, 21 => 1250, 32 => 1250 }

      expect(expected.keys.index_with { |panels| described_class.adequacy('micro', panels)['valor'] }).to eq(expected)
    end

    it 'devolve o valor de cada faixa do inversor string' do
      expected = { 4 => 760, 8 => 760, 9 => 950, 12 => 950, 13 => 1000, 16 => 1000, 17 => 1200, 20 => 1200, 21 => 1450, 32 => 1450,
                   33 => 1800, 46 => 1800, 47 => 2500, 70 => 2500, 71 => 3190, 100 => 3190, 101 => 5276, 200 => 5276 }

      expect(expected.keys.index_with { |panels| described_class.adequacy('string', panels)['valor'] }).to eq(expected)
    end

    it 'descreve a faixa usada como está na planilha' do
      expect(described_class.adequacy('micro', 7)).to eq('valor' => 550.0, 'faixa' => 'micro inversor, 4 a 8 placas')
      expect(described_class.adequacy('string', 85)).to eq('valor' => 3190.0, 'faixa' => 'inversor string, 70 a 100 placas')
    end

    it 'não inventa valor fora das faixas: pede o valor manual', :aggregate_failures do
      [['micro', 3], ['micro', 33], ['string', 3], ['string', 201], ['hibrido', 10], [nil, 10]].each do |type, panels|
        expect(described_class.adequacy(type, panels)).to be_nil
      end
      expect { described_class.new(kits: bluesun, panels: 40, type: 'micro').result }
        .to raise_error(described_class::NoAdequacyBand, /40 placas com micro inversor.*Informe o valor/)
    end

    it 'usa o valor manual quando informado' do
      dre = described_class.new(kits: bluesun, panels: 40, type: 'micro', adequacy: 1900).result

      expect(dre['adequacao']).to eq('valor' => 1900.0, 'faixa' => 'valor manual', 'manual' => true)
      expect(dre['dedutiveis'][2]).to include('nome' => 'Adequação (valor manual)', 'valor' => 1900.0)
    end
  end

  it 'monta o orçamento padrão com 25% de lucro líquido (caso Adriana, micro, 7 placas)', :aggregate_failures do
    dre = described_class.new(kits: bluesun, panels: 7, type: 'micro').result

    expect(dre['valor_projeto']).to eq(12_880.0)
    expect(dre['adequacao']).to eq('valor' => 550.0, 'faixa' => 'micro inversor, 4 a 8 placas', 'manual' => false)
    expect(dre['dedutiveis'][2]).to include('nome' => 'Adequação (micro inversor, 4 a 8 placas)', 'valor' => 550.0)
    expect(dre['total_dedutiveis']).to eq(8428.8)   # kit 7.178,80 + instalação 700 + adequação 550
    expect(dre['imposto']).to eq(445.12)            # 10% de (12.880 − 8.428,80)
    expect(dre['total_indedutiveis']).to eq(785.6)  # PLL 257,60 + brinde 78 + homologação 450
    expect(dre['lucro']).to eq(3220.48)
    expect(dre['custo_total']).to eq(9659.52)
    expect(dre['margem']).to eq(0.25)
    expect(dre['na_faixa']).to be(true)
    expect(dre['socios'].sum { |s| s['valor'] }).to be_within(0.02).of(3220.48)
    expect(dre['faixa']).to eq('minimo' => 11_591.31, 'padrao' => 12_879.24, 'maximo' => 13_989.52)
  end

  it 'não tem mais comissão nem seguro nos custos' do
    dre = described_class.new(kits: bluesun, panels: 7, type: 'micro').result
    names = (dre['dedutiveis'] + dre['indedutiveis']).reject { |l| l['valor'].zero? }.pluck('nome')

    expect(names).to eq(['Kit gerador (média de 1 fornecedor)', 'Instalação (7 placas)', 'Adequação (micro inversor, 4 a 8 placas)',
                         'PLL', 'Brinde', 'Homologação'])
  end

  it 'usa o preço MÉDIO do kit entre os fornecedores que cotaram' do
    kits = bluesun + [{ 'fornecedor' => 'AVT', 'valor' => 6821.20 }]
    dre = described_class.new(kits: kits, panels: 7, type: 'string')

    expect(dre.kit_cost).to eq(7000.0)
    expect(dre.result['dedutiveis'].first).to include('nome' => 'Kit gerador (média de 2 fornecedores)', 'valor' => 7000.0)
  end

  it 'arredonda o padrão para cima de R$ 10 em R$ 10' do
    dre = described_class.new(kits: bluesun, panels: 7, type: 'micro')

    expect(dre.price_for(0.25)).to be_within(0.01).of(12_879.24)
    expect(dre.standard_price).to eq(12_880)
  end

  it 'gera com outra margem quando pedido (30%)', :aggregate_failures do
    dre = described_class.new(kits: bluesun, panels: 7, type: 'micro').result(nil, margin: 0.30)

    expect(dre['valor_projeto']).to eq(13_990.0)
    expect(dre['margem']).to be_within(0.0005).of(0.30)
    expect(dre['padrao']).to eq(12_880)
  end

  it 'recalcula com o preço ajustado na mão e avisa quando sai da faixa de 18% a 30%', :aggregate_failures do
    dre = described_class.new(kits: bluesun, panels: 7, type: 'micro').result(11_000)

    expect(dre['valor_projeto']).to eq(11_000.0)
    expect(dre['margem']).to be < 0.18
    expect(dre['na_faixa']).to be(false)
    expect(dre['padrao']).to eq(12_880)
    expect(dre['lucro'] + dre['custo_total']).to be_within(0.01).of(11_000.0)
  end

  it 'aceita regras diferentes das de fábrica (ex.: rota e comissão)' do
    custom = described_class.new(kits: bluesun, panels: 7, type: 'micro', rules: { 'rota' => 300, 'comissao' => 0.08 })

    expect(custom.standard_price).to be > 12_880
    expect(custom.result['margem']).to be_within(0.001).of(0.25)
  end
end
