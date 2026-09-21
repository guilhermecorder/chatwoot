require 'rails_helper'

# 🎙️ rodada 195: config do Agente de Ligação no hub (permit, 422 do ao vivo, payload, "ver quem ligaria hoje")
RSpec.describe 'CRM settings — Agente de Ligação', type: :request do
  before { stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true) }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage) { pipeline.stages.create!(name: 'Envio de Orçamento', position: 1) }
  let!(:settings) { CrmSetting.create!(account: account, ai_config: {}) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }
  let(:headers) { admin.create_new_auth_token }

  def cfg
    CrmSetting.find_by(account: account).ai_config
  end

  it 'publica em sombra: grava colunas, tetos (dentro dos limites), janela e caixa; espelha a caixa em voice, nunca o prompt', :aggregate_failures do
    post "#{base}/update_ai",
         params: { agents: { voice: { enabled: true, mode: 'shadow', stage_ids: [stage.id, 999_999], silence_hours: 30, lookback_days: 10,
                                      max_attempts: 9, daily_cap: 30, live_days: [1, 1, 7], hours_start: '09:00', hours_end: '18:00',
                                      handoff_inbox_id: inbox.id, prompt: 'Passos custom da ligação' } } },
         headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    saved = cfg.dig('agents', 'voice')
    expect(saved).to include('enabled' => true, 'mode' => 'shadow', 'stage_ids' => [stage.id], 'silence_hours' => 30, 'lookback_days' => 10,
                             'max_attempts' => 5, 'daily_cap' => 30, 'live_days' => [1], 'handoff_inbox_id' => inbox.id,
                             'prompt' => 'Passos custom da ligação')
    expect(cfg['voice']).to include('enabled' => true, 'handoff_inbox_id' => inbox.id)
    expect(cfg['voice']).not_to have_key('prompt')

    agent = response.parsed_body.dig('agents', 'voice')
    expect(agent).to include('mode' => 'shadow', 'stage_ids' => [stage.id], 'silence_hours' => 30, 'lookback_days' => 10, 'max_attempts' => 5,
                             'daily_cap' => 30, 'live_days' => [1], 'hours_start' => '09:00', 'hours_end' => '18:00',
                             'handoff_inbox_id' => inbox.id, 'prompt' => 'Passos custom da ligação')
    expect(agent['default_prompt']).to include('LIGAÇÃO PARA LEAD NÃO RESPONSIVO')
    body = response.parsed_body
    expect(body['voice_events']).to eq([])
    expect(body['voice_shadow']).to include('items' => [], 'mode' => 'shadow')
    expect(body['voice_ready']).to be(false)
    expect(body['voice_live_now']).to be(false)
    expect(body).not_to have_key('voice_sync') # ElevenLabs não configurada: nada a subir
  end

  it 'Ao vivo sem coluna vigiada é recusado com frase clara' do
    post "#{base}/update_ai", params: { agents: { voice: { mode: 'live', enabled: true } } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('pelo menos uma coluna')
    expect(cfg.dig('agents', 'voice')).to be_nil
  end

  it 'Ao vivo sem a ElevenLabs configurada é recusado com frase clara' do
    post "#{base}/update_ai", params: { agents: { voice: { mode: 'live', enabled: true, stage_ids: [stage.id] } } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('ElevenLabs')
  end

  describe 'com a ElevenLabs configurada' do
    before { settings.update!(ai_config: { 'voice' => { 'enabled' => true, 'api_key' => 'el-teste', 'agent_id' => 'agent_1' } }) }

    it 'Ao vivo com coluna publica, sobe o prompt para a ElevenLabs e devolve o aviso quando a sincronização falha', :aggregate_failures do
      sync = instance_double(Crm::VoiceAgent::SyncService, perform: { ok: false, error: 'ElevenLabs fora do ar', log: [] })
      allow(Crm::VoiceAgent::SyncService).to receive(:new).with(account).and_return(sync)

      post "#{base}/update_ai", params: { agents: { voice: { mode: 'live', enabled: true, stage_ids: [stage.id], live_days: [] } } },
                                headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(cfg.dig('agents', 'voice')).to include('mode' => 'live', 'stage_ids' => [stage.id])
      expect(response.parsed_body['voice_ready']).to be(true)
      expect(response.parsed_body['voice_live_now']).to be(true)
      expect(response.parsed_body['voice_sync']).to eq('ok' => false, 'error' => 'ElevenLabs fora do ar')
    end

    it 'só o interruptor não sincroniza' do
      expect(Crm::VoiceAgent::SyncService).not_to receive(:new)
      post "#{base}/update_ai", params: { agents: { voice: { enabled: false } } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(cfg['voice']['enabled']).to be(false)
    end
  end

  it 'voice_shadow_run: roda a seleção agora em sombra, devolve a lista e grava o estado', :aggregate_failures do
    settings.update!(ai_config: { 'agents' => { 'voice' => { 'enabled' => true, 'stage_ids' => [stage.id] } } })
    maria = create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990001')
    Crm::Contact.create!(contact: maria, pipeline: pipeline, stage: stage)
    conversation = create(:conversation, account: account, inbox: inbox, contact: maria)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Segue o orçamento',
                     created_at: 30.hours.ago)

    post "#{base}/voice_shadow_run", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['count']).to eq(1)
    expect(body['items'].first).to include('contact_id' => maria.id, 'name' => 'Maria Silva', 'stage' => 'Envio de Orçamento')
    expect(body['items'].first['motivo']).to include('sem resposta há 30 h')
    expect(body).to include('ready' => false, 'live_now' => false)
    expect(cfg.dig('voice_state', 'shadow', 'items').size).to eq(1)
    expect(cfg.dig('voice_state', 'events')).to be_nil
    expect(Crm::CallCampaign.where(account_id: account.id).count).to eq(0)

    get base, headers: headers, as: :json
    expect(response.parsed_body.dig('ai', 'voice_shadow', 'items').size).to eq(1)
  end

  it 'voice_shadow_run só para administradores' do
    agent_user = create(:user, account: account, role: :agent)
    post "#{base}/voice_shadow_run", headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'ai_simulate aceita o agente voice e guarda o motivo da ligação na conversa de teste', :aggregate_failures do
    post "#{base}/ai_simulate", params: { agent: 'voice', objective: 'orçamento da catarata enviado, sem resposta há três dias' },
                                headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    conversation = account.conversations.find(response.parsed_body['conversation_id'])
    expect(conversation.additional_attributes).to include('cevico_simulado' => true, 'cevico_simulado_agent' => 'voice',
                                                          'cevico_simulado_objective' => 'orçamento da catarata enviado, sem resposta há três dias')
    expect(response.parsed_body['turns']).to eq([])
  end
end
