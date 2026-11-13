require 'rails_helper'

# ⚡ Orçamento automático: pronto → envia (PDF + fechamento); falhou → avisa a instabilidade e abre tarefa urgente.
RSpec.describe Crm::KitQuoteAutoJob do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:contact) { create(:contact, account: account, name: 'Marcos Bueno', phone_number: '+5519999990000') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    create(:user, account: account, role: :administrator, name: 'Fernando')
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'não vai aumentar')
  end

  it 'pronto: manda o orçamento oficial com a pergunta de fechamento e deixa nota', :aggregate_failures do
    quote = Crm::Quote.create!(account: account, contact: contact, price: 12_880, kind: 'micro', payload: { 'opcao' => { 'placas' => 7 } })
    quote.files.attach(io: StringIO.new('%PDF-1'), filename: 'Proposta-Marcos.pdf', content_type: 'application/pdf')
    allow(Crm::KitQuote::AutoBuild).to receive(:new).and_return(
      instance_double(Crm::KitQuote::AutoBuild, call: Crm::KitQuote::AutoBuild::Result.new(status: :pronto, quote: quote))
    )

    described_class.perform_now(conversation.id, 'atendente_agendamento')

    sent = conversation.messages.outgoing.order(:id).to_a
    expect(sent.first.content).to include('orçamento oficial')
    expect(sent.last.content).to include('É interessante para você fazer esse investimento agora?')
    expect(sent.map { |m| m.additional_attributes['cevico_ia_agent'] }.uniq).to eq(['atendente_agendamento'])
    expect(conversation.messages.where(message_type: :activity).last.content).to include('Orçamento automático ENVIADO')
    expect(quote.reload).to be_sent
    expect(conversation.reload.additional_attributes.dig('cevico_orcamento_auto', 'status')).to eq('enviado')
  end

  it 'falhou: avisa a instabilidade do fornecedor e abre tarefa urgente para gerar na mão', :aggregate_failures do
    allow(Crm::KitQuote::AutoBuild).to receive(:new).and_return(
      instance_double(Crm::KitQuote::AutoBuild,
                      call: Crm::KitQuote::AutoBuild::Result.new(status: :fornecedor_fora, motivo: 'nenhum fornecedor trouxe kit completo'))
    )

    described_class.perform_now(conversation.id, 'atendente_agendamento')

    expect(conversation.messages.outgoing.last.content).to include('instabilidade no sistema do fornecedor', 'alguns minutos')
    task = account.tasks.where(contact: contact).last
    expect(task.title).to include('Orçamento automático não saiu')
    expect(conversation.reload.additional_attributes.dig('cevico_orcamento_auto', 'status')).to eq('falhou')
  end

  it 'marca "gerando" e não deixa disparar duas vezes' do
    described_class.enqueue!(conversation, 'atendente_agendamento')
    expect(described_class.running?(conversation.reload)).to be(true)
  end
end
