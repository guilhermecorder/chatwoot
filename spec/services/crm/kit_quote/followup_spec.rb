require 'rails_helper'

# 💬 16/11/2026 (LIFE): botões "Mandar: forma de pagamento" e "Mandar: prazo" da caixa do orçamento, com os números da proposta.
RSpec.describe Crm::KitQuote::Followup do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza', phone_number: '+5519999990000') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:proposal) do
    { 'proposta' => { 'validade_dias' => 7 },
      'economia' => { 'mensal' => 380, 'anual' => 4560 },
      'investimento' => { 'preco_total' => 18_900, 'financiamento' => [{ 'parcelas' => 60, 'valor' => 520 }] } }
  end
  let(:quote) do
    Crm::Quote.create!(account: account, contact: contact, price: 18_900, kind: 'micro', payload: { 'proposta' => proposal },
                       created_at: Time.zone.parse('2026-11-14 15:00 -03:00'))
  end

  def open_window!
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
  end

  it 'mostra a prévia com os números da proposta', :aggregate_failures do
    preview = described_class.new(quote, 'pagamento').preview

    expect(preview['texto']).to start_with('Oi, Maria! Sobre o orçamento que eu te mandei')
    expect(preview['texto']).to include('em 60x de R$ 520, o sistema sai por R$ 31.200 no total',
                                        'até 6x sem juros: R$ 3.150 por mês, e o total fica nos R$ 18.900')
    expect(preview).to include('falta' => [], 'modelo' => 'life_orcamento_2_dias_pagamento', 'modelo_aprovado' => false)
    expect(described_class.new(quote, 'prazo').preview['texto'])
      .to include('vale até 21/11', 'são R$ 380 que vão para a CPFL')
  end

  it 'janela aberta: manda o texto na conversa' do
    open_window!

    expect(described_class.new(quote, 'prazo').call).to eq(:enviado)
    sent = conversation.messages.outgoing.last
    expect(sent.content).to start_with('Oi, Maria! O seu orçamento vale até 21/11.')
    expect(sent.additional_attributes).to include('cevico_orcamento_followup' => 'prazo')
  end

  it 'sem financiamento na proposta: não manda texto pela metade', :aggregate_failures do
    open_window!
    quote.update!(payload: { 'proposta' => proposal.merge('investimento' => { 'preco_total' => 18_900 }) })
    followup = described_class.new(quote, 'pagamento')

    expect(followup.preview).to include('texto' => nil, 'falta' => ['o financiamento'])
    expect(followup.call).to eq(:sem_dados)
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'janela fechada e modelo sem aprovação: avisa e não manda nada' do
    expect(described_class.new(quote, 'pagamento').call).to eq(:modelo_pendente)
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'janela fechada e modelo aprovado: manda o modelo com o nome e os números na ordem do modelo' do
    channel.update_columns(message_templates: [{ 'name' => 'life_orcamento_5_dias_prazo', 'status' => 'APPROVED', 'language' => 'pt_BR' }]) # rubocop:disable Rails/SkipsModelValidations
    service = instance_double(Crm::SendTemplateService, perform: conversation)
    allow(Crm::SendTemplateService).to receive(:new).and_return(service)

    expect(described_class.new(quote, 'prazo').call).to eq(:modelo_enviado)
    expect(Crm::SendTemplateService).to have_received(:new) do |source:, contact:|
      expect(contact).to eq(self.contact)
      expect(source.template_params).to include('name' => 'life_orcamento_5_dias_prazo',
                                                'processed_params' => { 'body' => { '1' => 'Maria', '2' => '21/11', '3' => 'R$ 380' } })
    end
  end

  it 'sem conversa no WhatsApp' do
    conversation.destroy!
    expect(described_class.new(quote, 'prazo').call).to eq(:sem_conversa)
  end
end
