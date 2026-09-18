require 'rails_helper'

RSpec.describe 'CEVICO Jornada API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let(:valid) do
    { name: 'Consulta amanhã', step: 'consulta', inbox_id: inbox.id,
      trigger: { kind: 'appointment', offset_days: -1, at: '09:00' },
      content: { mode: 'text', text: 'Olá {{primeiro_nome}}, sua consulta é {{data}} às {{hora}}.' } }
  end

  before { CrmSetting.create!(account: account, agenda_config: {}) }

  describe 'POST /crm/journey_messages' do
    it 'cria a regra para o admin e devolve o texto humano do gatilho' do
      post "#{base}/journey_messages", params: { journey_message: valid }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['when_label']).to eq('véspera · 09:00')
      expect(body['kind_label']).to eq('Dia da consulta (Agenda)')
      expect(body['stats']).to include('sent' => 0)
    end

    it 'recusa regra sem gatilho válido' do
      post "#{base}/journey_messages", params: { journey_message: valid.merge(trigger: { kind: 'x' }) },
                                       headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'barra atendente sem a área de campanhas' do
      post "#{base}/journey_messages", params: { journey_message: valid }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /crm/journey_messages' do
    it 'lista para o time, com etapas, tokens e configuração' do
      Crm::JourneyMessage.create!(valid.merge(account: account, inbox: inbox))
      get "#{base}/journey_messages", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['journey_messages'].size).to eq(1)
      expect(body['steps']).to include('cirurgia' => 'Cirurgia agendada')
      expect(body['tokens']).to include('primeiro_nome', 'endereco')
      expect(body['settings']['hours']).to eq('start' => '08:00', 'end' => '20:00')
    end
  end

  describe 'fila de hoje' do
    let(:message) { Crm::JourneyMessage.create!(valid.merge(account: account, inbox: inbox, approval: 'review')) }
    let(:contact) { create(:contact, account: account, phone_number: '+5511988887777') }
    let!(:send) do
      Crm::JourneySend.create!(account: account, journey_message: message, contact: contact, event_key: 'task:1',
                               scheduled_for: Time.current, status: 'pending_review')
    end

    it 'mostra os envios do dia e permite pular' do
      get "#{base}/journey_sends/queue", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success), response.body
      expect(response.parsed_body['sends'].map { |s| s['id'] }).to eq([send.id])

      post "#{base}/journey_sends/#{send.id}/skip", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(send.reload.status).to eq('skipped')
    end

    it 'aprova e despacha na hora (texto livre só com a janela aberta)' do
      post "#{base}/journey_sends/#{send.id}/approve", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['outcome']).to eq('failed')
      expect(send.reload.error).to include('janela de 24h')
    end
  end

  describe 'configuração' do
    it 'salva locais, horário e teto' do
      post "#{base}/journey_messages/update_settings",
           params: { places: { default: { unidade: 'Av. Paulista', endereco: 'Av. Paulista, 1000' } },
                     hours: { start: '09:00', end: '18:00' }, daily_cap: 120 },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body['settings']
      expect(body['places']['default']['unidade']).to eq('Av. Paulista')
      expect(body['hours']).to eq('start' => '09:00', 'end' => '18:00')
      expect(body['daily_cap']).to eq(120)
    end
  end
end
