require 'rails_helper'

# 🔒 Rodada 4 da auditoria (#229): os status sent/delivered/read chegam em
# paralelo; a marca de cobrança (item 303) é gravada pelo Cevico::AttributeMerge
# para não apagar o que outro escritor guardou na mensagem entre a leitura e o save!.
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
  let(:params) do
    { 'statuses' => [{ 'recipient_id' => '5511999990000', 'id' => 'wamid.abc', 'status' => 'delivered',
                       'pricing' => { 'billable' => true, 'pricing_model' => 'PMP', 'type' => 'regular', 'category' => 'service' } }] }
      .with_indifferent_access
  end

  it 'grava a cobrança sem apagar a chave que outro processo gravou depois que o status carregou a mensagem' do
    sync = instance_double(Whatsapp::IdentifierSyncService)
    allow(Whatsapp::IdentifierSyncService).to receive(:new).and_return(sync)
    allow(sync).to receive(:perform) do
      # roda depois de o serviço já ter a mensagem na mão e antes de ele gravar o status
      Cevico::AttributeMerge.merge!(Message.find(message.id)) { |a| a.merge('cevico_followup' => true) }
    end

    described_class.new(inbox: inbox, params: params).perform

    message.reload
    expect(message.status).to eq('delivered')
    expect(message.additional_attributes).to eq(
      'cevico_ia_agent' => 'atendente_agendamento', 'cevico_followup' => true,
      'cevico_wa_billing' => { 'billable' => true, 'category' => 'service', 'type' => 'regular', 'model' => 'PMP' }
    )
  end
end
