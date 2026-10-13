require 'rails_helper'

# 📱 Rodada 3 da auditoria (#62): a conversa da ligação/mensagem modelo é a do
# contact_inbox do número ATUAL — nunca a presa ao número antigo
RSpec.describe Crm::Calls::ConversationFinder do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'Maria', phone_number: '+5511999990001') }

  def conversation_for(phone_digits, **extra)
    ci = create(:contact_inbox, contact: contact, inbox: inbox, source_id: phone_digits)
    create(:conversation, { account: account, inbox: inbox, contact: contact, contact_inbox: ci }.merge(extra))
  end

  it 'mesmo número: reaproveita a conversa (e reabre se estava resolvida)', :aggregate_failures do
    existing = conversation_for('5511999990001', status: :resolved)
    finder = described_class.new(inbox: inbox, wa_id: '5511999990001', contact: contact)
    expect(finder.conversation).to eq(existing)
    expect(existing.reload).to be_open
  end

  it 'número trocado na ficha: conversa NOVA no número novo; a velha fica com o antigo', :aggregate_failures do
    old = conversation_for('5511999990001')
    contact.update!(phone_number: '+5511999990002')

    finder = described_class.new(inbox: inbox, wa_id: '5511999990002', contact: contact)
    conversation = finder.conversation

    expect(conversation).not_to eq(old)
    expect(conversation.contact_inbox.source_id).to eq('5511999990002')
    expect(old.reload.contact_inbox.source_id).to eq('5511999990001')
  end
end
