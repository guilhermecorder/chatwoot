require 'rails_helper'

# ⚡ Orçamento automático (LIFE, 12/11): ficha → cotação → opção completa mais barata → 25% → PDF → guardado.
RSpec.describe Crm::KitQuote::AutoBuild do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Marcos Bueno') }
  let(:option) do
    { 'fornecedor' => 'Bluesun', 'tipo' => 'micro', 'potencia_kwp' => 4.41, 'placas' => 7, 'preco' => 7020.71, 'frete' => 158.09,
      'total' => 7178.8, 'completa' => true, 'paineis' => '7 × Painel 630Wp Helius', 'inversor' => '2 × Micro Inversor Growatt 2,50kW',
      'equipamento' => { 'placa' => { 'quantidade' => 7, 'marca' => 'Helius', 'potencia_w' => 630 },
                         'inversores' => [{ 'quantidade' => 2, 'marca' => 'Growatt', 'potencia_kw' => 2.5 }], 'peso_kg' => 260.7 } }
  end
  let(:engine) { instance_double(Crm::KitQuote::Engine, run: { 'opcoes' => [option], 'medias' => Crm::KitQuote::Average.by_type([option]) }) }

  before do
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: { 'ficha_cliente' => { 'campos' => %w[conta telhado consumo_futuro cidade]
      .map { |k| { 'chave' => k, 'rotulo' => k } } } })
    Cevico::SettingMerge.merge_key!(account, :ai_config, 'kit_quote') { |c| (c || {}).merge('config' => { 'gerador_pdf' => { 'url' => 'http://gerador.test:3041' } }) }
    allow(Crm::KitQuote::Engine).to receive(:new).and_return(engine)
    stub_request(:post, 'http://gerador.test:3041/gerar').to_return(
      status: 200, body: { arquivos: [{ nome: 'Proposta-Marcos.pdf', tipo: 'application/pdf', base64: 'JVBERi0=' }], avisos: [] }.to_json
    )
  end

  def ficha(values)
    Crm::ClientSummary.write!(contact, values, by: 'Atendente')
  end

  it 'gera e guarda o orçamento a 25% com a conta e o telhado da ficha', :aggregate_failures do
    ficha('conta' => 'R$ 495,30 (foto da conta)', 'telhado' => 'telha de barro', 'consumo_futuro' => 'não vai aumentar', 'cidade' => 'Piracicaba/SP')

    result = described_class.new(account, contact).call

    expect(result.status).to eq(:pronto)
    quote = result.quote
    expect(quote.contact).to eq(contact)
    expect(quote.margin.to_f).to eq(0.25)
    expect(quote.payload).to include('automatico' => true, 'telhado' => 'ceramica')
    expect(quote.payload.dig('conta', 'hoje')).to eq(495.3)
    expect(quote.files.map { |f| f.filename.to_s }).to eq(['Proposta-Marcos.pdf'])
    expect(engine).to have_received(:run).with(kwh_month: (495.3 / 0.95).round, grid: 'bifasico', roof: 'ceramica')
  end

  it 'não começa sem a conta ou sem o telhado' do
    ficha('conta' => 'R$ 300')
    expect(described_class.new(account, contact).call).to have_attributes(status: :falta_dados, motivo: include('telhado'))
  end

  it 'aumento da tabela entra no orçamento: soma os kWh e aparece como acréscimo na conta', :aggregate_failures do
    ficha('conta' => 'R$ 285', 'telhado' => 'cerâmica', 'consumo_futuro' => 'vai pôr 2 ar-condicionados de 12 mil')

    result = described_class.new(account, contact).call

    expect(result.status).to eq(:pronto)
    expect(engine).to have_received(:run).with(kwh_month: 300 + 180, grid: 'bifasico', roof: 'ceramica')
    expect(result.quote.payload.dig('conta', 'acrescimos')).to eq([{ 'rotulo' => '2 ar-condicionados (12.000 BTU)', 'valor' => 171.0 }])
  end

  it 'aumento fora da tabela fica com a equipe' do
    ficha('conta' => 'R$ 300', 'telhado' => 'cerâmica', 'consumo_futuro' => 'vai pôr uma sauna')
    expect(described_class.new(account, contact).call.status).to eq(:com_aumento)
  end

  it 'sem kit completo de nenhum fornecedor = fornecedor fora' do
    ficha('conta' => 'R$ 300', 'telhado' => 'cerâmica')
    allow(engine).to receive(:run).and_return('opcoes' => [option.merge('completa' => false, 'falta' => 'estrutura')], 'medias' => {})
    expect(described_class.new(account, contact).call.status).to eq(:fornecedor_fora)
  end

  it 'gerador de PDF com erro não guarda nada' do
    ficha('conta' => 'R$ 300', 'telhado' => 'cerâmica')
    stub_request(:post, 'http://gerador.test:3041/gerar').to_return(status: 500, body: { erro: 'quebrou' }.to_json)
    expect(described_class.new(account, contact).call).to have_attributes(status: :erro, motivo: include('quebrou'))
    expect(Crm::Quote.count).to eq(0)
  end
end
