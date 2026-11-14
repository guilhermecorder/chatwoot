require 'rails_helper'

# ✏️ Editar um orçamento gerado (Guilherme, 13/11/2026): nome, cidade/UF, telhado e validade; os PDFs saem de novo.
RSpec.describe Crm::KitQuote::Edit do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Dete') }
  let(:payload) do
    {
      'cliente' => { 'nome' => 'Dete', 'cidade' => 'Piracicaba', 'uf' => 'SP' },
      'proposta' => { 'cliente' => { 'nome' => 'Dete', 'cidade' => 'Piracicaba', 'uf' => 'SP', 'distribuidora' => 'CPFL' },
                      'proposta' => { 'data' => '2026-11-13', 'validade_dias' => 7 }, 'telhado' => { 'tipo' => 'Telha cerâmica' } },
      'justificativa' => { 'cliente' => 'Dete', 'cidade' => 'Piracicaba/SP' }
    }
  end
  let(:quote) { Crm::Quote.create!(account: account, contact: contact, price: 10_420, kind: 'micro', payload: payload) }
  let(:pdf) { { 'nome' => 'Proposta-Dete.pdf', 'tipo' => 'application/pdf', 'base64' => Base64.strict_encode64('%PDF-novo') } }
  let(:renderer) { instance_double(Crm::KitQuote::Renderer, available?: true) }

  before do
    quote.attach_rendered([{ 'nome' => 'Proposta-antiga.pdf', 'tipo' => 'application/pdf', 'base64' => Base64.strict_encode64('%PDF-velho') }])
  end

  it 'troca o nome em todo o payload, gera os PDFs de novo e substitui os arquivos' do
    allow(renderer).to receive(:render).and_return('arquivos' => [pdf])

    result = described_class.new(quote, { nome: 'Dete Aparecida', uf: 'sp' }, renderer).call

    expect(result.ok).to be(true)
    quote.reload
    expect(quote.payload.dig('proposta', 'cliente', 'nome')).to eq('Dete Aparecida')
    expect(quote.payload.dig('cliente', 'nome')).to eq('Dete Aparecida')
    expect(quote.payload.dig('justificativa', 'cliente')).to eq('Dete Aparecida')
    expect(quote.files.map { |f| f.filename.to_s }).to eq(['Proposta-Dete.pdf'])
    novo_nome = hash_including('cliente' => hash_including('nome' => 'Dete Aparecida'))
    expect(renderer).to have_received(:render).with(hash_including('proposta' => novo_nome))
  end

  it 'muda telhado e validade (limitada a 30 dias) sem mexer no preço' do
    allow(renderer).to receive(:render).and_return('arquivos' => [pdf])

    described_class.new(quote, { telhado: 'Telha metálica', validade_dias: '90' }, renderer).call

    quote.reload
    expect(quote.payload.dig('proposta', 'telhado', 'tipo')).to eq('Telha metálica')
    expect(quote.payload.dig('proposta', 'proposta', 'validade_dias')).to eq(30)
    expect(quote.price.to_f).to eq(10_420.0)
  end

  it 'sem gerador de PDF, salva os dados, mantém os PDFs antigos e avisa' do
    off = instance_double(Crm::KitQuote::Renderer, available?: false)

    result = described_class.new(quote, { nome: 'Dete A.' }, off).call

    expect(result.aviso).to include('gerador de PDF não está ligado')
    expect(quote.reload.payload.dig('proposta', 'cliente', 'nome')).to eq('Dete A.')
    expect(quote.files.map { |f| f.filename.to_s }).to eq(['Proposta-antiga.pdf'])
  end

  it 'mostra os valores atuais para o formulário' do
    expect(described_class.current(quote)).to eq(
      'nome' => 'Dete', 'cidade' => 'Piracicaba', 'uf' => 'SP', 'telhado' => 'Telha cerâmica', 'validade_dias' => 7
    )
  end
end
