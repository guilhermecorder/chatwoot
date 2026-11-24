require 'rails_helper'

# 🔢 16/11/2026 (LIFE): números da proposta para o follow-up de fechamento (pagamento, prazo, economia).
RSpec.describe Crm::KitQuote::Numbers do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }
  let(:proposal) do
    { 'proposta' => { 'data' => '2026-11-14', 'validade_dias' => 7 },
      'economia' => { 'mensal' => 380, 'anual' => 4560, 'em_25_anos' => 257_000 },
      'investimento' => { 'preco_total' => 18_900,
                          'financiamento' => [{ 'parcelas' => 36, 'valor' => 780 }, { 'parcelas' => 60, 'valor' => 520 }] } }
  end
  let(:quote) do
    Crm::Quote.create!(account: account, contact: contact, price: 18_900, kind: 'micro', payload: { 'proposta' => proposal },
                       created_at: Time.zone.parse('2026-11-14 15:00 -03:00'))
  end

  it 'monta os textos com os números da proposta', :aggregate_failures do
    numbers = described_class.new(quote)
    expect(numbers[:preco]).to eq('R$ 18.900')
    expect(numbers[:cartao_6x]).to eq('R$ 3.150')
    expect(numbers[:financiamento]).to eq('60x de R$ 520') # o maior prazo
    expect(numbers[:financiamento_total]).to eq('R$ 31.200')
    expect(numbers[:validade]).to eq('21/11')
    expect(numbers[:economia_mes]).to eq('R$ 380')
    expect(numbers[:economia]).to eq('R$ 4.560 por ano')
  end

  it '24/11: economia em 10 anos e a economia investida a 1% ao mês por 10 anos', :aggregate_failures do
    proposal['economia']['em_10_anos'] = 66_500
    numbers = described_class.new(quote)
    expect(numbers[:economia_10]).to eq('R$ 66.500')
    expect(numbers[:investido_10]).to eq('R$ 87.415') # 380 × ((1,01^120 − 1) / 0,01)
  end

  it 'a validade editada no Gerador vale' do
    proposal['proposta']['validade_dias'] = 3
    expect(described_class.new(quote)[:validade]).to eq('17/11')
  end

  it 'sem financiamento ou sem preço: nil (quem usa decide pular)', :aggregate_failures do
    quote.update!(payload: { 'proposta' => proposal.merge('investimento' => {}) })
    numbers = described_class.new(quote)
    expect(numbers[:financiamento]).to be_nil
    expect(numbers[:financiamento_total]).to be_nil
    expect(numbers[:preco]).to be_nil
    expect(numbers[:cartao_6x]).to be_nil
  end

  it '.for pega o orçamento ativo mais novo do contato (lixeira fora)', :aggregate_failures do
    quote
    Crm::Quote.create!(account: account, contact: contact, price: 1, kind: 'micro', payload: {}, deleted_at: Time.current)
    expect(described_class.for(contact)[:preco]).to eq('R$ 18.900')
    expect(described_class.for(create(:contact, account: account))).to be_nil
  end
end
