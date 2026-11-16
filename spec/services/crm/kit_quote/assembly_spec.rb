require 'rails_helper'

# 🧩 Montar na mão (15/11): N placas de um tamanho, com o preço real da cotação. O fornecedor monta pelo consumo,
# então o sistema acha o consumo que dá exatamente N placas e confere o que voltou.
RSpec.describe Crm::KitQuote::Assembly do
  let(:config) { Crm::KitQuote::DEFAULTS }

  # um "fornecedor" que arredonda pelo próprio fator (130 kWh por kWp, diferente do nosso)
  let(:engine) do
    Class.new do
      attr_reader :asked

      def initialize
        @asked = []
      end

      def run(kwh_month:, grid:, roof:, margin: true)
        raise 'montar na mão não leva folga' if margin

        @asked << kwh_month
        kwp = kwh_month / 130.0
        options = [[620, 'Ronma Solar', 6000], [630, 'Helius', 5900]].map do |watts, brand, price|
          count = (kwp * 1000 / watts).ceil
          { 'tipo' => 'string', 'placas' => count, 'total' => price + (count * 100), 'fornecedor' => 'Bluesun',
            'equipamento' => { 'placa' => { 'quantidade' => count, 'marca' => brand, 'potencia_w' => watts } } }
        end
        { 'consumo_kwh_mes' => kwh_month, 'rede' => grid, 'telhado' => roof, 'opcoes' => options }
      end
    end.new
  end

  it 'chega às placas pedidas mesmo quando o fornecedor arredonda diferente, e põe essas opções primeiro', :aggregate_failures do
    result = described_class.new(engine, config).run(panels: 9, watts: 630, brand: 'Helius', grid: 'bifasico', roof: 'ceramica')

    first = result['opcoes'].first
    expect(first).to include('placas' => 9, 'montagem' => true)
    expect(first.dig('equipamento', 'placa', 'marca')).to eq('Helius')
    expect(result['montagem']).to include('placas' => 9, 'potencia_w' => 630, 'exatas' => 1, 'kwp' => 5.67)
    expect(engine.asked.size).to be <= described_class::TRIES
  end

  it 'aceita só quantidade e tamanho válidos', :aggregate_failures do
    expect(described_class.valid?(6, 620)).to be(true)
    expect(described_class.valid?(0, 620)).to be(false)
    expect(described_class.valid?(6, 20)).to be(false)
  end
end
