require 'rails_helper'

# 🤖📞 item 333 (achados da auditoria de 07/10): o discador reconfere cada
# pessoa NA HORA de ligar, respeita a trava geral, os dias e o modo do agente,
# e manda o roteiro de LIGAR em cada ligação.
RSpec.describe Crm::VoiceAgent::CampaignDialerJob do
  let(:account) { create(:account) }
  let(:tz) { Crm::VoiceAgent::Settings::TZ }
  let(:now) { tz.parse('2026-10-07 10:00') } # quarta-feira
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:voice_cfg) do
    { 'enabled' => true, 'api_key' => 'el-teste', 'agent_id' => 'agent_1', 'whatsapp_phone_number_id' => 'pn_1',
      'handoff_inbox_id' => channel.inbox.id, 'permission_template' => { 'name' => 'pode_ligar', 'language' => 'pt_BR' },
      'hours' => { 'start' => '08:00', 'end' => '19:00' }, 'call_days' => [1, 2, 3, 4, 5] }
  end
  let!(:settings) { CrmSetting.create!(account: account, ai_config: { 'voice' => voice_cfg }) }
  let(:maria) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990001') }
  let(:campaign) do
    Crm::CallCampaign.create!(account: account, name: 'Reativar', objective: 'reativar', status: :processing, daily_cap: 10,
                              concurrency: 5, audience: {}, stats: {})
  end
  let(:client) { instance_double(Crm::VoiceAgent::Client) }
  let(:bodies) { [] }

  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    allow(Crm::VoiceAgent::Client).to receive(:new).and_return(client)
    allow(client).to receive(:whatsapp_outbound_call) do |body|
      bodies << body
      { 'success' => true, 'conversation_id' => "conv_#{bodies.size}" }
    end
    allow(Redis::LockManager).to receive(:new).and_return(instance_double(Redis::LockManager, lock: true, unlock: true))
  end

  # só a conta do teste (o banco local pode ter campanhas de outras contas)
  def dial!(at = now)
    job = described_class.new
    job.instance_variable_set(:@now, at)
    job.send(:run_account, account, [campaign.reload])
  end

  def row_for(contact)
    campaign.campaign_contacts.find_by(contact_id: contact.id)
  end

  it 'liga com o roteiro de LIGAR e a 1ª frase de ligar com o nome', :aggregate_failures do
    campaign.campaign_contacts.create!(contact: maria, status: 'queued')

    dial!

    expect(row_for(maria).status).to eq('calling')
    agent = bodies.first.dig(:conversation_initiation_client_data, :conversation_config_override, :agent)
    expect(agent[:first_message]).to start_with('Olá, Maria! Aqui é a assistente virtual da CEVICO. A gente conversou')
    expect(agent.dig(:prompt, :prompt)).to include('LIGAÇÃO PARA LEAD NÃO RESPONSIVO')
  end

  it 'reconfere na hora: não liga para quem pediu para parar, é de parceiro ou recusou a ligação', :aggregate_failures do
    quiet = create(:contact, account: account, name: 'Quieta', phone_number: '+5511999990002')
    quiet.add_labels(['nao_perturbe'])
    partner = create(:contact, account: account, name: 'Parceira', phone_number: '+5511999990003')
    partner.add_labels(['of_clinica_x'])
    refused = create(:contact, account: account, name: 'Recusou', phone_number: '+5511999990004',
                               additional_attributes: { 'cevico_call_permission' => { 'status' => 'reject',
                                                                                      'replied_at' => (now - 3.days).iso8601 } })
    [quiet, partner, refused].each { |c| campaign.campaign_contacts.create!(contact: c, status: 'queued') }

    dial!

    expect(bodies).to be_empty
    expect(row_for(quiet).error).to eq('Pediu para não ser incomodado')
    expect(row_for(partner).error).to eq('Paciente de clínica parceira')
    expect(row_for(refused).error).to eq('Recusou ligações nos últimos 30 dias')
  end

  it 'sem a trava geral dos robôs (CEVICO_RESPONDERS_LIVE) não disca nada' do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', false)
    campaign.campaign_contacts.create!(contact: maria, status: 'queued')

    dial!

    expect(bodies).to be_empty
    expect(row_for(maria).status).to eq('queued')
  end

  it 'respeita os dias escolhidos: no sábado a fila fica parada' do
    campaign.campaign_contacts.create!(contact: maria, status: 'queued')

    dial!(tz.parse('2026-10-10 10:00')) # sábado

    expect(bodies).to be_empty
    expect(row_for(maria).status).to eq('queued')
  end

  describe 'campanha automática de leads parados' do
    let(:campaign) do
      Crm::CallCampaign.create!(account: account, name: '🤖 Leads não responsivos — 07/10', objective: 'retomar', status: :processing,
                                daily_cap: 10, concurrency: 5, audience: { 'kind' => 'unresponsive_leads', 'objectives' => {} },
                                stats: {}, created_at: now - 1.hour)
    end

    def agent!(mode)
      settings.update!(ai_config: settings.ai_config.merge('agents' => { 'voice' => { 'enabled' => true, 'mode' => mode } }))
    end

    it 'só disca com o card do agente AO VIVO (em sombra a fila espera)', :aggregate_failures do
      agent!('shadow')
      campaign.campaign_contacts.create!(contact: maria, status: 'queued')
      dial!
      expect(bodies).to be_empty

      agent!('live')
      dial!
      expect(row_for(maria).status).to eq('calling')
    end

    it 'não liga para quem respondeu depois de entrar na fila', :aggregate_failures do
      agent!('live')
      row = campaign.campaign_contacts.create!(contact: maria, status: 'queued', created_at: now - 30.minutes)
      talk = create(:conversation, account: account, inbox: channel.inbox, contact: maria)
      create(:message, account: account, inbox: channel.inbox, conversation: talk, message_type: :incoming, content: 'oi',
                       created_at: now - 5.minutes)

      travel_to(now) { dial! }

      expect(bodies).to be_empty
      expect(row.reload.error).to eq('Respondeu depois de entrar na fila')
    end

    it 'a fila que sobrou de um dia anterior é descartada', :aggregate_failures do
      agent!('live')
      campaign.update_column(:created_at, now - 1.day) # rubocop:disable Rails/SkipsModelValidations
      campaign.campaign_contacts.create!(contact: maria, status: 'queued')

      dial!

      expect(bodies).to be_empty
      expect(row_for(maria).status).to eq('skipped')
      expect(row_for(maria).error).to eq('Fila de um dia anterior')
    end
  end
end
