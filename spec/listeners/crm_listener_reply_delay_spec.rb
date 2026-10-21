require 'rails_helper'

# ⏱️ item 200: o Atendente responde entre 5 e 10 s da mensagem (reply_delay_seconds)
RSpec.describe CrmListener do
  include ActiveJob::TestHelper

  around do |example|
    old = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = old
  end

  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def fire_incoming
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def configure(extra = {})
    Crm::Contact.where(contact_id: contact.id).delete_all
    CrmSetting.create!(account: account, ai_config: { 'agents' => { 'atendente_agendamento' =>
      { 'enabled' => true, 'mode' => 'shadow', 'inbox_ids' => [inbox.id], 'no_card' => true }.merge(extra) } })
  end

  it 'padrão: 6 s de espera' do
    configure
    freeze_time do
      expect { fire_incoming }.to have_enqueued_job(Crm::ResponderAgentJob).at(6.seconds.from_now)
    end
  end

  it 'respeita reply_delay_seconds e prende entre 3 e 30 s' do
    configure('reply_delay_seconds' => 9)
    freeze_time do
      expect { fire_incoming }.to have_enqueued_job(Crm::ResponderAgentJob).at(9.seconds.from_now)
    end
    expect(listener.send(:responder_delay, { 'reply_delay_seconds' => 1 })).to eq(3.seconds)
    expect(listener.send(:responder_delay, { 'reply_delay_seconds' => 99 })).to eq(30.seconds)
    expect(listener.send(:responder_delay, {})).to eq(6.seconds)
  end
end
