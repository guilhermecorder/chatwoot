require 'rails_helper'

# 💸 item 303: Gasto do WhatsApp — só admin; tarifas; sincronizar com a Meta
RSpec.describe 'CEVICO WhatsApp Spend API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/whatsapp_spend" }

  describe 'GET /crm/whatsapp_spend' do
    it 'devolve os blocos da tela para o admin' do
      get base, params: { preset: 'last7' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['rates']).to include('currency' => 'BRL', 'service' => 0.035)
      expect(body['attributed']).to include('messages' => 0, 'cost' => 0)
      expect(body['meta']['synced']).to be(false)
      expect(body['service_charged_from']).to eq('2026-10-01')
    end

    it 'barra atendente' do
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /crm/whatsapp_spend/rates' do
    it 'salva as tarifas e volta ao padrão quando vazio' do
      post "#{base}/rates", params: { marketing: '0.40', service: '0.05', currency: 'BRL' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['rates']).to include('marketing' => 0.4, 'service' => 0.05, 'utility' => 0.035, 'edited' => true)

      post "#{base}/rates", params: {}, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['rates']).to include('marketing' => 0.3217, 'edited' => false)
    end
  end

  describe 'POST /crm/whatsapp_spend/sync' do
    it 'roda a leitura da Meta na hora até 95 dias' do
      service = instance_double(Crm::WhatsappPricingSyncService, call: { ok: true, rows: 3 })
      allow(Crm::WhatsappPricingSyncService).to receive(:new).with(account: account, days: 35).and_return(service)

      post "#{base}/sync", params: { days: 35 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('ok' => true, 'rows' => 3)
    end

    it 'manda para a fila quando pede o histórico longo' do
      expect do
        post "#{base}/sync", params: { days: 450 }, headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Crm::WhatsappPricingSyncJob).with(account.id, 450)
      expect(response.parsed_body).to include('queued' => true, 'days' => 450)
    end
  end
end
