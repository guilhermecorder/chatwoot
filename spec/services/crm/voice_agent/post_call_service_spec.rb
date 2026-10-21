require 'rails_helper'

RSpec.describe Crm::VoiceAgent::PostCallService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:phone) { '5511999990000' }
  let!(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: "+#{phone}") }

  before do
    CrmSetting.create!(account: account, ai_config: { 'voice' => { 'enabled' => true, 'handoff_inbox_id' => inbox.id, 'llm' => 'gemini-2.5-flash' } })
  end

  def payload(conversation_id, direction: 'inbound', duration: 130, status: 'done', outcome: 'agendou')
    {
      'type' => 'post_call_transcription',
      'data' => {
        'agent_id' => 'sim_agent', 'conversation_id' => conversation_id, 'status' => status,
        'transcript' => [
          { 'role' => 'agent', 'message' => 'Olá! Aqui é a assistente virtual da CEVICO.' },
          { 'role' => 'user', 'message' => 'Quero marcar uma consulta.', 'tool_calls' => [] },
          { 'role' => 'agent', 'message' => '', 'tool_calls' => [{ 'tool_name' => 'horarios_livres' }] }
        ],
        'metadata' => { 'start_time_unix_secs' => 5.minutes.ago.to_i, 'call_duration_secs' => duration, 'cost_fiat' => 0.0312,
                        'termination_reason' => 'end_call tool was called.',
                        'whatsapp' => { 'direction' => direction, 'whatsapp_user_id' => phone } },
        'analysis' => { 'transcript_summary' => 'Paciente marcou consulta.',
                        'data_collection_results' => { 'resultado' => { 'value' => outcome } } }
      }
    }
  end

  it 'cria a ligação da IA com transcrição, resultado, card, cable e uso de IA', :aggregate_failures do
    expect { described_class.new(account: account, payload: payload('conv_1')).perform }
      .to change(Crm::Call, :count).by(1)
      .and change(Crm::AiUsage, :count).by(1)

    call = Crm::Call.find_by!(account: account, provider_call_id: 'conv_1')
    expect(call).to be_completed
    expect(call.handled_by).to eq('ai')
    expect(call.contact).to eq(contact)
    expect(call.duration).to eq(130)
    expect(call.outcome).to eq('agendou')
    expect(call.summary).to eq('Paciente marcou consulta.')
    expect(call.transcript).to eq("Assistente: Olá! Aqui é a assistente virtual da CEVICO.\nPaciente: Quero marcar uma consulta.\n" \
                                  '(ferramenta: horarios_livres)')
    expect(call.cost_usd.to_f).to eq(0.0312)
    card = call.conversation.messages.find(call.message_id)
    expect(card.content).to include('🤖 Ligação atendida pela assistente virtual')
    expect(card.content).to include('agendou consulta')
    expect(card.content_attributes['cevico_call']['handled_by']).to eq('ai')
    expect(ActionCableBroadcastJob).to have_been_enqueued.with(["account_#{account.id}"], 'cevico_call.ended', anything)
    expect(Crm::AiUsage.last.agent_key).to eq('voice')
  end

  it 'é idempotente: a reentrega do webhook atualiza a mesma ligação' do
    described_class.new(account: account, payload: payload('conv_2')).perform
    expect { described_class.new(account: account, payload: payload('conv_2', duration: 200)).perform }.not_to change(Crm::Call, :count)
    expect(Crm::Call.find_by!(account: account, provider_call_id: 'conv_2').duration).to eq(200)
  end

  it 'duração zero vira perdida com nao_atendeu' do
    described_class.new(account: account, payload: payload('conv_3', duration: 0, outcome: '')).perform

    call = Crm::Call.find_by!(account: account, provider_call_id: 'conv_3')
    expect(call).to be_missed
    expect(call.end_reason).to eq('not_answered')
    expect(call.outcome).to eq('nao_atendeu')
  end

  it 'fecha o contato da campanha com o resultado e conclui a campanha', :aggregate_failures do
    campaign = Crm::CallCampaign.create!(account: account, name: 'Reativação', status: :processing, apply_label: 'ligou-ia')
    row = campaign.campaign_contacts.create!(contact: contact, status: 'calling', provider_conversation_id: 'conv_4', called_at: Time.current)

    described_class.new(account: account, payload: payload('conv_4', direction: 'outbound', outcome: 'remarcou')).perform

    row.reload
    expect(row.status).to eq('done')
    expect(row.outcome).to eq('remarcou')
    call = Crm::Call.find(row.call_id)
    expect(call).to be_outbound
    expect(call.campaign_id).to eq(campaign.id)
    expect(call.card_content).to include('A assistente ligou para o paciente')
    expect(campaign.reload).to be_completed
    expect(campaign.stats['done']).to eq(1)
    expect(contact.reload.label_list).to include('ligou-ia')
  end

  it 'anexa o áudio como gravação mp3' do
    described_class.new(account: account, payload: payload('conv_5')).perform
    audio = { 'type' => 'post_call_audio', 'data' => { 'conversation_id' => 'conv_5', 'full_audio' => Base64.strict_encode64('mp3-bytes') } }

    described_class.new(account: account, payload: audio).perform

    call = Crm::Call.find_by!(account: account, provider_call_id: 'conv_5')
    expect(call.recording).to be_attached
    expect(call.recording_mime).to eq('audio/mpeg')
  end
end
