require 'rails_helper'

# 💵 item 318: cotação PTAX do Banco Central — fim de semana herda a sexta
RSpec.describe Crm::UsdRateService do
  before do
    travel_to Time.zone.parse('2026-10-05 12:00')
    Rails.cache.clear
  end

  it 'preenche todos os dias com o último dia útil', :aggregate_failures do
    stub_request(:get, /olinda\.bcb\.gov\.br/).to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { value: [{ cotacaoVenda: 5.20, dataHoraCotacao: '2026-10-01 13:10:35.4' },
                      { cotacaoVenda: 5.22, dataHoraCotacao: '2026-10-02 13:03:16.2' }] }.to_json
    )
    rates = described_class.rates_for(Date.new(2026, 10, 1), Date.new(2026, 10, 4))

    expect(rates).to eq(Date.new(2026, 10, 1) => 5.20, Date.new(2026, 10, 2) => 5.22,
                        Date.new(2026, 10, 3) => 5.22, Date.new(2026, 10, 4) => 5.22)
  end

  it 'sem resposta do Banco Central devolve vazio (a tela pede o dólar manual)' do
    stub_request(:get, /olinda\.bcb\.gov\.br/).to_return(status: 500)
    expect(described_class.rates_for(Date.new(2026, 10, 1), Date.new(2026, 10, 2))).to eq({})
  end
end
