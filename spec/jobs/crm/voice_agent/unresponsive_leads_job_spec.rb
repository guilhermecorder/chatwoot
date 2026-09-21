require 'rails_helper'

# 📞 rodada 195: de hora em hora — sombra grava a lista; ao vivo enfileira na campanha do dia
RSpec.describe Crm::VoiceAgent::UnresponsiveLeadsJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage) { pipeline.stages.create!(name: 'Envio de Orçamento', position: 1) }
  let(:now) { Crm::VoiceAgent::Settings::TZ.now }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'shadow', 'stage_ids' => [stage.id], 'daily_cap' => 5 } }
  let(:voice_cfg) { { 'enabled' => true, 'api_key' => 'el-teste', 'agent_id' => 'agent_1', 'hours' => { 'start' => '08:00', 'end' => '19:00' } } }
  let!(:settings) { CrmSetting.create!(account: account, ai_config: { 'agents' => { 'voice' => agent_cfg }, 'voice' => voice_cfg }) }
  let!(:maria) do
    contact = create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990001')
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Segue o orçamento',
                     created_at: now - 30.hours)
    contact
  end

  before { stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true) }

  def state
    settings.reload.ai_config['voice_state'] || {}
  end

  # as specs rodam no banco de desenvolvimento (em transação): contar só desta conta
  def campaigns
    Crm::CallCampaign.where(account_id: account.id)
  end

  it 'SOMBRA: grava a lista "ligaria hoje" e registra o evento, sem discar nada', :aggregate_failures do
    described_class.perform_now(now)
    shadow = state['shadow']
    expect(shadow).to include('date' => now.to_date.to_s, 'mode' => 'shadow')
    expect(shadow['items'].size).to eq(1)
    expect(shadow['items'].first).to include('contact_id' => maria.id, 'name' => 'Maria Silva', 'stage' => 'Envio de Orçamento')
    expect(state['events'].first).to include('type' => 'ligaria')
    expect(state['events'].first['note']).to include('1 pessoa(s)').and include('Maria Silva')
    expect(campaigns.count).to eq(0)

    # mesma lista no giro seguinte: sem evento repetido
    expect { described_class.perform_now(now + 1.hour) }.not_to(change { state['events'].size })
  end

  it 'card desligado: não faz nada' do
    settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'voice' => { 'enabled' => false } }))
    described_class.perform_now(now)
    expect(state).to eq({})
  end

  describe 'AO VIVO (modo live + trava + janela + ElevenLabs configurada)' do
    before { settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'voice' => { 'mode' => 'live', 'live_days' => [] } })) }

    it 'enfileira na campanha do dia com o motivo por pessoa e o discador faz o resto', :aggregate_failures do
      described_class.perform_now(now)
      campaign = campaigns.first
      expect(campaign.name).to eq("🤖 Leads não responsivos — #{now.strftime('%d/%m')}")
      expect(campaign).to be_processing
      expect(campaign.daily_cap).to eq(5)
      expect(campaign.first_message).to eq(Crm::VoiceAgent::Script::UNRESPONSIVE_FIRST_MESSAGE)
      expect(campaign.hours).to eq('start' => '08:00', 'end' => '19:00')
      rows = campaign.campaign_contacts
      expect(rows.count).to eq(1)
      expect(rows.first).to have_attributes(contact_id: maria.id, status: 'queued')
      expect(campaign.audience.dig('objectives', maria.id.to_s)).to include('Envio de Orçamento')
      expect(state['shadow']).to include('mode' => 'live', 'campaign_id' => campaign.id)
      expect(state['shadow']['items'].first).to include('contact_id' => maria.id, 'status' => 'queued')
      expect(state['events'].first).to include('type' => 'enfileirou')

      # giro seguinte: mesma campanha, ninguém duplicado, sem evento novo
      expect { described_class.perform_now(now + 1.hour) }.not_to(change { [campaigns.count, rows.count, state['events'].size] })
    end

    it 'o discador manda o motivo da pessoa como {{campanha_objetivo}}' do
      described_class.perform_now(now)
      campaign = campaigns.first
      row = campaign.campaign_contacts.first
      voice_settings = Crm::VoiceAgent::Settings.new(account)
      body = Crm::VoiceAgent::CampaignDialerJob.new.send(:outbound_body, campaign, row, maria, '5511999990001', voice_settings)
      expect(body.dig(:conversation_initiation_client_data, :dynamic_variables, :campanha_objetivo)).to include('Envio de Orçamento')
      expect(body.dig(:conversation_initiation_client_data, :conversation_config_override, :agent, :first_message)).to start_with('Olá, Maria!')
    end

    it 'fora da janela (dia da semana) volta para sombra' do
      other_day = (now.wday + 1) % 7
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'voice' => { 'live_days' => [other_day] } }))
      described_class.perform_now(now)
      expect(campaigns.count).to eq(0)
      expect(state['shadow']).to include('mode' => 'shadow')
    end

    it 'sem a ElevenLabs configurada fica em sombra' do
      settings.update!(ai_config: settings.ai_config.merge('voice' => voice_cfg.except('agent_id')))
      described_class.perform_now(now)
      expect(campaigns.count).to eq(0)
      expect(state['shadow']).to include('mode' => 'shadow')
    end

    it 'com a trava do servidor fechada fica em sombra' do
      stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', false)
      described_class.perform_now(now)
      expect(campaigns.count).to eq(0)
    end
  end

  it 'shadow! sem log (botão "Ver quem ligaria hoje") devolve a lista e grava o estado sem evento', :aggregate_failures do
    items = described_class.shadow!(account, agent_cfg, now: now, log: false)
    expect(items.pluck('contact_id')).to eq([maria.id])
    expect(state['shadow']['items'].size).to eq(1)
    expect(state['events']).to be_nil
  end
end
