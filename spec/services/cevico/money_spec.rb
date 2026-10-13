require 'rails_helper'

# 💰 Rodada 5 da auditoria (#192): um só jeito de ler dinheiro. Vírgula =
# centavos; ponto só é milhar em grupos de 3 dígitos; "R$", espaços e números
# de verdade são aceitos; o que não é dinheiro vira nil (nunca valor errado).
RSpec.describe Cevico::Money do
  {
    '5000' => 5000.0,
    '5.000' => 5000.0, # o achado: antes virava 5,00 no .xlsx de fechamento
    '5.000,00' => 5000.0,
    'R$ 5.000' => 5000.0,
    'R$5.000,00' => 5000.0,
    'R $ 5.000' => 5000.0, # espaço entre o R e o $
    '$ 5.000' => 5000.0,
    "R$\u00A05.000,00" => 5000.0, # espaço "duro" que o Excel cola
    '12.500' => 12_500.0,
    '1.234.567' => 1_234_567.0,
    '3900,5' => 3900.5,
    '3900' => 3900.0,
    '  3.900,00  ' => 3900.0,
    '0,50' => 0.5,
    '24187.8' => 24_187.8, # número cru do XML do Excel: ponto decimal
    '1234.567' => 1234.57, # 4 dígitos antes do ponto não é milhar
    '0.500' => 0.5, # zero à esquerda não é milhar
    '-150,00' => -150.0,
    3900 => 3900.0,
    3900.5 => 3900.5,
    BigDecimal('4500.25') => 4500.25
  }.each do |entrada, esperado|
    it "lê #{entrada.inspect} como #{esperado}" do
      expect(described_class.parse(entrada)).to eq(esperado)
    end
  end

  [nil, '', '   ', 'à combinar', '1,2,3', '5.00.0', '5,', 'R$', '1.500 - 2.000', '1e5',
   '5,000', '3900,500'].each do |entrada|
    it "não inventa valor para #{entrada.inspect}" do
      expect(described_class.parse(entrada)).to be_nil
    end
  end

  it 'loose: tolera texto em volta (planilha do Google), sem perder a regra do milhar' do
    expect(described_class.parse('R$ 5.000,00 à vista', loose: true)).to eq(5000.0)
    expect(described_class.parse('5.000 reais', loose: true)).to eq(5000.0)
    expect(described_class.parse('5.000 reais')).to be_nil
    # centavos com mais de 2 dígitos = texto misturado ou milhar americano
    expect(described_class.parse('1.234,56 / 2x', loose: true)).to be_nil
    expect(described_class.parse('5,000', loose: true)).to be_nil
  end

  it 'parse_with_note: lê o número do começo e ignora a anotação, mas recusa dois números', :aggregate_failures do
    expect(described_class.parse_with_note('5.000,00 (pago)')).to eq(5000.0)
    expect(described_class.parse_with_note('R$ 3.900 à vista')).to eq(3900.0)
    expect(described_class.parse_with_note('$ 5.000')).to eq(5000.0)
    expect(described_class.parse_with_note('12.500')).to eq(12_500.0)
    expect(described_class.parse_with_note(3900)).to eq(3900.0)
    expect(described_class.parse_with_note('2x 2.500,00')).to be_nil
    expect(described_class.parse_with_note('1.500 - 2.000')).to be_nil
    expect(described_class.parse_with_note('à combinar')).to be_nil
  end

  describe 'os três caminhos usam a mesma regra' do
    it 'planilha do Google (SheetsSurgeryService#parse_money)' do
      service = Crm::SheetsSurgeryService.allocate
      expect(service.send(:parse_money, '5.000')).to eq(5000.0)
      expect(service.send(:parse_money, '12.500')).to eq(12_500.0)
      expect(service.send(:parse_money, '')).to eq(0.0)
    end

    # 🛡️ Rodada 6 (#260): os outros caminhos de dinheiro digitado
    it 'Tabela de preços (Cevico::PriceList.sanitize_row): "8.490" é R$ 8.490, não R$ 8,49', :aggregate_failures do
      row, problem = Cevico::PriceList.sanitize_row(group: 'Catarata (por olho)', name: 'Trifocal', price: '8.490', promo_price: '7.990,00')
      expect(problem).to be_nil
      expect(row).to include('price' => 8490.0, 'promo_price' => 7990.0, 'unit' => 'por_olho')

      expect(Cevico::PriceList.sanitize_row(name: 'Lasik', price: 5700, unit: 'dois_olhos').first).to include('price' => 5700.0)
      expect(Cevico::PriceList.sanitize_row(name: 'Lasik', price: '12.500', unit: 'dois_olhos').first).to include('price' => 12_500.0)
      # o que não é dinheiro continua sendo "falta o preço" (nunca vira R$ 5,00)
      expect(Cevico::PriceList.sanitize_row(name: 'Lasik', price: '5,000', unit: 'dois_olhos').last).to include('falta o preço')
      expect(Cevico::PriceList.sanitize_row(name: 'Lasik', price: 'à combinar', unit: 'dois_olhos').last).to include('falta o preço')
    end

    it 'planilha de fechamento .xlsx (ClosingSheetReader#parse_value): texto "5.000" é R$ 5.000', :aggregate_failures do
      reader = Crm::ClosingSheetReader.allocate
      expect(reader.send(:parse_value, '5.000')).to eq(5000.0)
      expect(reader.send(:parse_value, 'R$ 12.500,00')).to eq(12_500.0)
      expect(reader.send(:parse_value, '5.000,00 (pago)')).to eq(5000.0)
      expect(reader.send(:parse_value, 'à combinar')).to eq(0.0)
    end

    it 'colagem telefone;valor (ExternalSurgeriesController#parse_value)' do
      controller = Api::V1::Accounts::Crm::ExternalSurgeriesController.new
      expect(controller.send(:parse_value, 'R$ 5.000')).to eq(5000.0)
      expect(controller.send(:parse_value, '3900,5')).to eq(3900.5)
      expect(controller.send(:parse_value, '0')).to be_nil
      expect(controller.send(:parse_value, 'abc')).to be_nil
    end
  end
end
