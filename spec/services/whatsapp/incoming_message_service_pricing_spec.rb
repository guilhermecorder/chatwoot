require 'rails_helper'

# 💸 item 303: o status do WhatsApp traz `pricing` (cobrada? categoria?) —
# guardamos na própria mensagem sem apagar o que já estava lá
RSpec.describe Whatsapp::IncomingMessageService do
  before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

  let!(:whatsapp_channel) { create(:channel_whatsapp, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511999990000') }
  let(:conversation) { create(:conversation, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact) }
  let!(:message) do
    create(:message, account: inbox.account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     source_id: 'wamid.abc', status: :sent, additional_attributes: { 'cevico_ia_agent' => 'atendente_agendamento' })
  end

  def status_params(pricing, status: 'delivered')
    {
      'statuses' => [{ 'recipient_id' => '5511999990000', 'id' => 'wamid.abc', 'status' => status, 'pricing' => pricing }]
    }.with_indifferent_access
  end

  it 'guarda a marca de cobrança ao lado do carimbo do robô' do
    described_class.new(inbox: inbox, params: status_params(
      { 'billable' => true, 'pricing_model' => 'PMP', 'type' => 'regular', 'category' => 'service' }
    )).perform

    message.reload
    expect(message.status).to eq('delivered')
    expect(message.additional_attributes['cevico_ia_agent']).to eq('atendente_agendamento')
    expect(message.additional_attributes['cevico_wa_billing']).to eq(
      'billable' => true, 'category' => 'service', 'type' => 'regular', 'model' => 'PMP'
    )
  end

  it 'marca a mensagem grátis da janela de 24h' do
    described_class.new(inbox: inbox, params: status_params(
      { 'billable' => false, 'pricing_model' => 'PMP', 'type' => 'free_customer_service', 'category' => 'utility' }
    )).perform

    expect(message.reload.additional_attributes['cevico_wa_billing']).to include('billable' => false, 'type' => 'free_customer_service',
                                                                                 'category' => 'utility')
  end

  it 'sem pricing no status, não mexe nos atributos' do
    described_class.new(inbox: inbox, params: status_params(nil, status: 'read')).perform

    message.reload
    expect(message.status).to eq('read')
    expect(message.additional_attributes).to eq('cevico_ia_agent' => 'atendente_agendamento')
  end
end
