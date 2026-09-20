require 'rails_helper'

RSpec.describe 'CEVICO Calls API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let!(:call) do
    Crm::Call.create!(account: account, inbox: inbox, contact: contact, conversation: conversation, meta_call_id: 'wacid.1',
                      direction: :inbound, status: :ringing, wa_id: '5511999990000', started_at: Time.current,
                      sdp_offer: 'v=0', simulated: true)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm/calls" }

  describe 'POST /crm/calls/:id/accept' do
    it 'atende a ligação e registra quem atendeu' do
      post "#{base}/#{call.id}/accept", params: { sdp_answer: 'v=0' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['status']).to eq('accepted')
      expect(body['user']['id']).to eq(agent.id)
      expect(call.reload.answered_at).to be_present
      expect(ActionCableBroadcastJob).to have_been_enqueued.with(
        ["account_#{account.id}"], 'cevico_call.taken', hash_including(user_id: agent.id)
      )
    end

    it 'devolve 409 quando outra pessoa já atendeu' do
      call.update!(status: :accepted, user: admin, answered_at: Time.current)
      post "#{base}/#{call.id}/accept", params: { sdp_answer: 'v=0' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to include(admin.available_name)
    end
  end

  describe 'POST /crm/calls/:id/reject' do
    it 'recusa, grava o card na conversa e encerra' do
      post "#{base}/#{call.id}/reject", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(call.reload).to be_rejected
      card = conversation.messages.find(call.message_id)
      expect(card.content_attributes['cevico_call']['status']).to eq('rejected')
      expect(ActionCableBroadcastJob).to have_been_enqueued.with(["account_#{account.id}"], 'cevico_call.ended', anything)
    end
  end

  describe 'GET /crm/calls/dashboard' do
    it 'devolve os números para o admin' do
      call.update!(status: :completed, user: agent, answered_at: 1.minute.ago, ended_at: Time.current, duration: 60)
      get "#{base}/dashboard", params: { preset: 'month' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['kpis']['received']).to eq(1)
      expect(body['kpis']['answered']).to eq(1)
      expect(body['by_hour'].size).to eq(24)
      expect(body['recent'].first['id']).to eq(call.id)
    end

    it 'barra atendente sem a área de relatórios' do
      get "#{base}/dashboard", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /crm/calls' do
    it 'lista as ligações do paciente' do
      get base, params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['calls'].size).to eq(1)
      expect(response.parsed_body['meta']['total']).to eq(1)
    end
  end

  # ── item 176: ambiente Chamadas ──
  describe 'GET /crm/calls/overview' do
    it 'devolve números, comparação, ao vivo e perdidas sem retorno para o time (sem concessão)' do
      Crm::Call.create!(account: account, inbox: inbox, contact: contact, meta_call_id: 'wacid.missed', direction: :inbound,
                        status: :missed, end_reason: 'not_answered', wa_id: '5511999990000', started_at: 5.minutes.ago,
                        ended_at: 4.minutes.ago, simulated: true)
      get "#{base}/overview", params: { preset: 'today' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['kpis']['received']).to eq(2)
      expect(body['previous']['received']).to eq(0)
      expect(body['live'].map { |c| c['id'] }).to eq([call.id])
      expect(body['missed_pending'].size).to eq(1)
      expect(body['by_inbox'].first['name']).to eq(inbox.name)
    end

    it 'não lista como pendente a perdida que a clínica já retornou' do
      missed = Crm::Call.create!(account: account, inbox: inbox, contact: contact, meta_call_id: 'wacid.m2', direction: :inbound,
                                 status: :missed, wa_id: '5511999990000', started_at: 10.minutes.ago, simulated: true)
      Crm::Call.create!(account: account, inbox: inbox, contact: contact, meta_call_id: 'wacid.out', direction: :outbound,
                        status: :completed, wa_id: '5511999990000', started_at: 2.minutes.ago, simulated: true)
      get "#{base}/overview", params: { preset: 'today' }, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['missed_pending'].map { |c| c['id'] }).not_to include(missed.id)
    end
  end

  describe 'GET /crm/calls (lista)' do
    it 'live=1 devolve só o que está tocando ou em atendimento' do
      Crm::Call.create!(account: account, inbox: inbox, meta_call_id: 'wacid.done', direction: :inbound, status: :completed,
                        wa_id: '5511999990001', started_at: 1.hour.ago, simulated: true)
      get base, params: { live: 1 }, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['calls'].map { |c| c['id'] }).to eq([call.id])
    end

    it 'busca por nome do paciente ou telefone' do
      contact.update!(name: 'Maria Oliveira')
      Crm::Call.create!(account: account, inbox: inbox, meta_call_id: 'wacid.other', direction: :inbound, status: :completed,
                        display_name: 'Outro', wa_id: '5521888880000', started_at: 1.hour.ago, simulated: true)
      get base, params: { q: 'oliveira', preset: 'today' }, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['calls'].map { |c| c['id'] }).to eq([call.id])

      get base, params: { q: '(21) 88888', preset: 'today' }, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['calls'].map { |c| c['display_name'] }).to eq(['Outro'])
    end
  end

  describe 'POST /crm/calls/:id/returned' do
    it 'marca a perdida como retornada e avisa todo mundo' do
      call.update!(status: :missed, end_reason: 'not_answered', ended_at: Time.current, sdp_offer: nil)
      expect(Crm::Calls::Broadcaster).to receive(:push).with(account, 'cevico_call.ended', hash_including(:call))
      post "#{base}/#{call.id}/returned", params: { note: 'liguei do fixo' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['returned_at']).to be_present
      expect(call.reload.events.last['event']).to eq('returned')
    end

    it 'recusa em ligação ainda tocando' do
      post "#{base}/#{call.id}/returned", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /crm/calls/export' do
    it 'devolve um CSV com cabeçalho em pt-BR e uma linha por ligação' do
      get "#{base}/export", params: { preset: 'today' }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('text/csv')
      lines = response.body.lines
      expect(lines.first).to start_with('Data;Hora;Direção;Situação')
      expect(lines.size).to eq(2)
    end
  end
end
