require 'rails_helper'

RSpec.describe Crm::Calls::WebhookService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:wa_id) { '5511999990000' }
  let(:meta_call_id) { 'wacid.teste123' }
  let(:fake_sdp) { "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=simulated\r\n" }
  let(:connect_value) do
    {
      'contacts' => [{ 'wa_id' => wa_id, 'profile' => { 'name' => 'Maria Simulada' } }],
      'calls' => [{ 'id' => meta_call_id, 'from' => wa_id, 'to' => '5511888880000', 'event' => 'connect',
                    'direction' => 'USER_INITIATED', 'timestamp' => Time.current.to_i.to_s,
                    'session' => { 'sdp_type' => 'offer', 'sdp' => fake_sdp } }]
    }
  end

  before do
    CrmSetting.create!(account: account,
                       agenda_config: { 'calls' => { 'enabled' => true, 'inbox_id' => inbox.id, 'ring_user_ids' => [agent.id] } })
  end

  def terminate_value(duration: 0, status: 'COMPLETED')
    { 'calls' => [{ 'id' => meta_call_id, 'from' => wa_id, 'event' => 'terminate', 'direction' => 'USER_INITIATED',
                    'timestamp' => Time.current.to_i.to_s, 'status' => status, 'duration' => duration }] }
  end

  def perform(value)
    described_class.new(channel: channel, value: value, simulated: true).perform
  end

  describe 'connect (paciente ligou)' do
    it 'cria a ligação tocando, o contato e a conversa, e avisa o time' do
      expect { perform(connect_value) }
        .to change(Crm::Call, :count).by(1)
        .and change(Contact, :count).by(1)
        .and change(Conversation, :count).by(1)

      call = Crm::Call.last
      expect(call).to be_ringing
      expect(call.sdp_offer).to eq(fake_sdp)
      expect(call.contact.phone_number).to eq("+#{wa_id}")
      expect(call.contact.name).to eq('Maria Simulada')
      expect(call.conversation.inbox_id).to eq(inbox.id)
      expect(ActionCableBroadcastJob).to have_been_enqueued.with(
        ["account_#{account.id}"], 'cevico_call.ringing', hash_including(ring_user_ids: [agent.id])
      )
    end

    it 'manda quem toca primeiro e a espera da cascata (rodada 2)' do
      other = create(:user, account: account, role: :agent)
      CrmSetting.find_by!(account: account).update!(
        agenda_config: { 'calls' => { 'enabled' => true, 'inbox_id' => inbox.id, 'ring_user_ids' => [agent.id, other.id],
                                      'ring_first_user_ids' => [agent.id, 999_999], 'ring_cascade_seconds' => 20 } }
      )
      perform(connect_value)
      expect(ActionCableBroadcastJob).to have_been_enqueued.with(
        ["account_#{account.id}"], 'cevico_call.ringing',
        hash_including(ring_user_ids: [agent.id, other.id], ring_first_user_ids: [agent.id], ring_cascade_seconds: 20)
      )
    end

    it 'com VÁRIAS caixas, cada uma toca para os seus atendentes (pedido 18/09)' do
      other = create(:user, account: account, role: :agent)
      channel_b = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                            validate_provider_config: false, phone_number: '+5511777770000')
      settings = CrmSetting.find_by!(account: account)
      settings.update!(agenda_config: { 'calls' => { 'enabled' => true, 'inboxes' => [
        { 'inbox_id' => inbox.id, 'ring_user_ids' => [agent.id] },
        { 'inbox_id' => channel_b.inbox.id, 'ring_user_ids' => [other.id], 'ring_first_user_ids' => [other.id], 'ring_cascade_seconds' => 30 }
      ] } })
      cfg = Crm::Calls::Settings.new(account)
      expect(cfg.inbox_ids).to eq([inbox.id, channel_b.inbox.id])
      expect(cfg.inbox?(channel_b.inbox)).to be(true)

      described_class.new(channel: channel_b, value: connect_value, simulated: true).perform
      expect(ActionCableBroadcastJob).to have_been_enqueued.with(
        ["account_#{account.id}"], 'cevico_call.ringing',
        hash_including(ring_user_ids: [other.id], ring_first_user_ids: [other.id], ring_cascade_seconds: 30)
      )
      expect(Crm::Call.last.inbox_id).to eq(channel_b.inbox.id)

      # ligar PARA o paciente: sai pela caixa da conversa dele (a pedida), senão pela primeira
      contact = Crm::Call.last.contact
      expect(cfg.outbound_inbox_for(contact: contact, preferred_id: channel_b.inbox.id)).to eq(channel_b.inbox)
      expect(cfg.outbound_inbox_for(contact: contact, preferred_id: 999_999)).to eq(channel_b.inbox) # última conversa
      expect(cfg.outbound_inbox_for(contact: create(:contact, account: account))).to eq(inbox)
    end

    it 'não duplica a ligação quando a Meta reenvia o webhook' do
      perform(connect_value)
      expect { perform(connect_value) }.not_to change(Crm::Call, :count)
    end
  end

  describe 'terminate' do
    let(:call) { Crm::Call.find_by!(account: account, meta_call_id: meta_call_id) }

    before { perform(connect_value) }

    it 'sem ninguém atender vira perdida, com card na conversa e conversa aberta' do
      call.conversation.update!(status: :resolved)
      perform(terminate_value)

      call.reload
      expect(call).to be_missed
      expect(call.end_reason).to eq('not_answered')
      expect(call.sdp_offer).to be_nil
      card = call.conversation.messages.find(call.message_id)
      expect(card.content).to eq('📵 Chamada perdida')
      expect(card.content_attributes['cevico_call']['status']).to eq('missed')
      expect(call.conversation.reload).to be_open
      expect(ActionCableBroadcastJob).to have_been_enqueued.with(["account_#{account.id}"], 'cevico_call.missed', anything)
    end

    it 'perdida vira aviso no Radar e some quando alguém retorna (rodada 3)' do
      perform(terminate_value)
      alerts = CrmSetting.find_by!(account: account).ai_config.dig('opportunity_state', 'alerts')
      alert = alerts.find { |a| a['kind'] == 'missed_call' }
      expect(alert).to include('call_id' => call.id, 'contact_name' => 'Maria Simulada')
      expect(alert['motivo']).to include('ninguém atendeu')
      expect(Crm::Calls::RadarAlert.still_open?(account, alert)).to be(true)

      # a atendente respondeu na conversa → o aviso perde a razão de existir
      call.reload.conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing,
                                                sender: agent, content: 'Oi, vi que ligou!')
      expect(Crm::Calls::RadarAlert.still_open?(account, alert)).to be(false)
    end

    it 'depois de atendida vira concluída com a duração da Meta' do
      call.update!(status: :accepted, user: agent, answered_at: 30.seconds.ago)
      perform(terminate_value(duration: 222))

      call.reload
      expect(call).to be_completed
      expect(call.duration).to eq(222)
      expect(call.talk_seconds).to eq(222)
      card = call.conversation.messages.find(call.message_id)
      expect(card.content).to include("atendida por #{agent.available_name}")
      expect(card.content).to include('3 min 42 s')
      expect(ActionCableBroadcastJob).to have_been_enqueued.with(["account_#{account.id}"], 'cevico_call.ended', anything)
    end
  end
end
