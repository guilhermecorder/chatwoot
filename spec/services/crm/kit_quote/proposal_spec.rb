require 'rails_helper'

# 📄 Dados da proposta e da justificativa (LIFE). Caso real da Adriana (11/11/2026): 7 placas Helius 630 W,
# micro Growatt, telha cerâmica, conta de R$ 300 + 2 ares = R$ 500, 490 kWh por mês.
# Os números têm que bater entre os dois documentos e com o DRE.
RSpec.describe Crm::KitQuote::Proposal do
  let(:config) { Crm::KitQuote::DEFAULTS }
  let(:quotes) do
    [{ 'fornecedor' => 'Bluesun', 'valor' => 7178.80, 'detalhe' => 'kit R$ 7.020,71 + frete R$ 158,09, com estrutura', 'entra_na_media' => true },
     { 'fornecedor' => 'AVT', 'valor' => 7011.82, 'detalhe' => 'kit R$ 7.011,82, sem estrutura do telhado e frete', 'entra_na_media' => false }]
  end
  let(:option) do
    { 'fornecedor' => 'Bluesun', 'tipo' => 'micro', 'potencia_kwp' => 4.41, 'placas' => 7, 'preco' => 7020.71, 'frete' => 158.09,
      'paineis' => '7 × Painel Fotovoltaico 630Wp Bifacial Helius', 'inversor' => '2 × Micro Inversor Growatt 2,50kW',
      'equipamento' => { 'placa' => { 'quantidade' => 7, 'marca' => 'Helius', 'potencia_w' => 630 },
                         'inversores' => [{ 'quantidade' => 2, 'marca' => 'Growatt', 'potencia_kw' => 2.5 }], 'peso_kg' => 260.7 } }
  end
  let(:bill) { { 'hoje' => 300.0, 'acrescimos' => [{ 'rotulo' => '2 ares-condicionados', 'valor' => 200.0 }], 'consumo_kwh' => 490.0 } }
  let(:dre) { Crm::KitQuote::Dre.new(kits: quotes.select { |q| q['entra_na_media'] }, panels: 7, type: 'micro').result }
  let(:documents) do
    described_class.new(config: config, client: { 'nome' => 'Adriana' }, bill: bill, roof: 'ceramica', option: option, quotes: quotes,
                        dre: dre, date: Date.new(2026, 11, 11)).call
  end
  let(:proposal) { documents['proposta'] }
  let(:justification) { documents['justificativa'] }

  it 'monta a proposta do cliente', :aggregate_failures do
    expect(proposal['cliente']).to eq('nome' => 'Adriana', 'cidade' => 'Piracicaba', 'uf' => 'SP', 'distribuidora' => 'CPFL')
    expect(proposal['conta']).to eq('valor_mensal' => 500.0, 'consumo_kwh_mes' => 490,
                                    'composicao' => [{ 'rotulo' => 'Conta de luz hoje', 'valor' => 300.0 },
                                                     { 'rotulo' => '2 ares-condicionados', 'valor' => 200.0 }])
    expect(proposal['telhado']).to eq('tipo' => 'Telha cerâmica')
    expect(proposal['sistema']).to include('potencia_kwp' => 4.41, 'producao_kwh_mes' => 520, 'producao_kwh_ano' => 6240,
                                           'area_m2' => 20, 'peso_kg' => 261, 'incidencia_solar' => 4.91)
    expect(proposal.dig('sistema', 'paineis')).to eq([{ 'quantidade' => 7, 'marca' => 'Helius', 'potencia_w' => 630 }])
    expect(proposal.dig('sistema', 'inversores')).to eq([{ 'quantidade' => 2, 'tipo' => 'Microinversor', 'marca' => 'Growatt', 'modelo' => '2,5K' }])
    expect(proposal['garantias'].last).to eq('item' => 'Microinversores', 'anos' => 12, 'cobre' => 'contra defeito de fabricação')
    expect(proposal['economia']).to eq('mensal' => 500.0, 'anual' => 6000.0, 'em_10_anos' => 73_500, 'em_25_anos' => 429_000)
  end

  it 'usa o preço do DRE e a condição nova do cartão', :aggregate_failures do
    investment = proposal['investimento']

    expect(investment['preco_total']).to eq(12_880.0)
    expect(investment['cartao']).to eq('6x sem juros ou até 20x no cartão (favor nos consultar)')
    expect(investment['financiamento']).to eq([{ 'parcelas' => 36, 'valor' => 635 }, { 'parcelas' => 48, 'valor' => 558 },
                                               { 'parcelas' => 60, 'valor' => 516 }])
    expect(investment['preco_antes']).to eq('de' => 37_000, 'ate' => 50_000)
  end

  it 'monta a justificativa: consumo, sistema, cotações e média', :aggregate_failures do
    expect(justification['consumo']).to include('total_reais' => 500.0, 'total_kwh' => 490, 'tarifa' => 1.035)
    today, extra = justification.dig('consumo', 'linhas')
    expect(today).to eq('rotulo' => 'Conta de luz hoje', 'reais' => 300.0, 'kwh' => 290, 'nota' => 'R$ 300 ÷ R$ 1,035 por kWh')
    expect(extra).to eq('rotulo' => '2 ares-condicionados', 'reais' => 200.0, 'kwh' => 200, 'nota' => 'estimativa')
    expect(justification['sistema']).to include(
      'formula' => '490 kWh ÷ (4,91 h de sol × 30 dias × 80% de aproveitamento) = 4,16 kWp', 'potencia_necessaria_kwp' => 4.16,
      'placas' => 7, 'potencia_placa_w' => 630, 'potencia_kwp' => 4.41, 'producao_kwh_mes' => 520, 'cobertura' => 1.06,
      'equipamento' => '7 placas Helius 630 W + 2 microinversores Growatt 2,5K + estrutura para telha cerâmica'
    )
    expect(justification['kit']).to include('media' => 7178.8, 'fornecedores_na_media' => 1, 'nao_cotados' => %w[Belenergy Cordeiro])
    expect(justification.dig('kit', 'cotacoes').pluck('fornecedor', 'entra_na_media')).to eq([['Bluesun', true], ['AVT', false]])
  end

  it 'descreve a adequação com a faixa usada e o valor, nos custos e no que conferir', :aggregate_failures do
    expect(justification['adequacao']).to eq('valor' => 550.0, 'faixa' => 'micro inversor, 4 a 8 placas', 'manual' => false)
    expect(justification['custos']).to include('nome' => 'Adequação (micro inversor, 4 a 8 placas)', 'valor' => 550.0, 'taxa' => nil)
    expect(justification['conferir']).to include('Adequação pela tabela: micro inversor, 4 a 8 placas = R$ 550,00.')
    expect(justification['conferir']).to include(
      'Kit: média de 1 fornecedor com cotação completa (Bluesun). Fora da média: AVT (cotação sem estrutura ou sem frete).',
      'Parcelas a 3,5% ao mês (taxa a confirmar): 36x R$ 635, 48x R$ 558, 60x R$ 516.'
    )
  end

  it 'fecha a conta: custos somam o custo total e custo + lucro dá o valor da proposta', :aggregate_failures do
    summary = justification['resumo']

    expect(summary).to eq('valor_projeto' => 12_880.0, 'custo_total' => 9659.52, 'lucro' => 3220.48, 'margem' => 0.25)
    expect(justification['custos'].sum { |c| c['valor'] }.round(2)).to eq(summary['custo_total'])
    expect((summary['custo_total'] + summary['lucro']).round(2)).to eq(proposal.dig('investimento', 'preco_total'))
    expect(justification['custos'].pluck('nome')).to eq(
      ['Kit gerador (média de 1 fornecedor)', 'Instalação (7 placas)', 'Adequação (micro inversor, 4 a 8 placas)',
       'Imposto (10% sobre valor menos dedutíveis)', 'PLL', 'Brinde', 'Homologação']
    )
  end

  it 'mostra a faixa de 18%, 25% e 30% com o padrão marcado e o lucro por sócio', :aggregate_failures do
    pricing = justification['preco']

    expect(pricing['faixa']).to eq([
                                     { 'margem' => 0.18, 'valor' => 11_591.31, 'padrao' => false },
                                     { 'margem' => 0.25, 'valor' => 12_879.24, 'padrao' => true, 'selo' => 'Padrão' },
                                     { 'margem' => 0.30, 'valor' => 13_989.52, 'padrao' => false }
                                   ])
    expect(pricing['regra']).to eq('Orçamento padrão com 25% de lucro líquido, arredondado para cima de R$ 10 em R$ 10. ' \
                                   'Sem comissão e sem seguro; imposto de 10%.')
    expect(pricing['por_kwp']).to eq(2920.63)
    expect(pricing['socios'].pluck('nome')).to eq(%w[Vini Ac Fernando Guilherme])
  end

  context 'with o preço ajustado na mão para fora da faixa' do
    let(:dre) { Crm::KitQuote::Dre.new(kits: quotes.select { |q| q['entra_na_media'] }, panels: 7, type: 'micro').result(11_000) }

    it 'marca o preço escolhido na faixa e avisa no que conferir', :aggregate_failures do
      chosen = justification.dig('preco', 'faixa').find { |r| r['padrao'] }

      expect(chosen).to include('valor' => 11_000.0, 'selo' => 'Escolhido')
      expect(justification.dig('preco', 'regra')).to include('Preço ajustado: R$ 11.000,00', 'o padrão de 25% seria R$ 12.880,00')
      expect(justification['conferir']).to include(a_string_matching(/ATENÇÃO: lucro de \d+,\d+%, fora da faixa de 18% a 30%/))
      expect(proposal.dig('investimento', 'preco_total')).to eq(11_000.0)
    end
  end

  context 'with inversor string e sem acréscimo na conta' do
    let(:bill) { { 'hoje' => 500.0, 'acrescimos' => [], 'consumo_kwh' => 0 } }
    let(:option) do
      { 'fornecedor' => 'Bluesun', 'tipo' => 'string', 'potencia_kwp' => 4.41, 'placas' => 7,
        'paineis' => '7 × Painel 630Wp Helius', 'inversor' => '1 × Inversor On-grid Leapton 4kW S1X-4K1P-Y' }
    end
    let(:dre) { Crm::KitQuote::Dre.new(kits: [{ 'fornecedor' => 'Bluesun', 'valor' => 7085.68 }], panels: 7, type: 'string').result }

    it 'usa a adequação do string, calcula o consumo pela tarifa e pede para confirmar a garantia do inversor', :aggregate_failures do
      expect(justification['adequacao']).to include('valor' => 760.0, 'faixa' => 'inversor string, 4 a 8 placas')
      expect(proposal['conta']).to eq('valor_mensal' => 500.0, 'consumo_kwh_mes' => 483)
      expect(proposal['garantias'].last).to include('item' => 'Inversor', 'anos' => 10)
      expect(justification['conferir']).to include('Garantia do inversor (10 anos): confirmar com o fabricante.')
      expect(proposal.dig('sistema', 'inversores').first).to include('quantidade' => 1, 'tipo' => 'Inversor')
    end
  end
end
