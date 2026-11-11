require 'rails_helper'

# 📨 item 391: Configurações → Modelos → "Criar modelo" (só administrador)
RSpec.describe 'CEVICO WhatsApp Templates API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/whatsapp_templates" }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
  end
  let(:payload) do
    { inbox_ids: [inbox.id], name: 'retomar_agendamento', category: 'MARKETING', body: 'Oi! Ficou faltando só escolher o dia da sua avaliação.',
      buttons: ['Quero ver os horários'] }
  end

  before do
    stub_request(:get, %r{graph\.facebook\.com/.*/message_templates})
      .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'envia o modelo para a Meta e devolve o resultado por número' do
    stub_request(:post, %r{graph\.facebook\.com/.*/message_templates})
      .to_return(status: 200, body: { id: '55', status: 'PENDING' }.to_json, headers: { 'Content-Type' => 'application/json' })

    post base, params: payload, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('ok' => true)
    expect(response.parsed_body['results'].first).to include('inbox_id' => inbox.id, 'status' => 'PENDING')
  end

  it 'devolve 422 com a explicação quando o modelo está errado' do
    post base, params: payload.merge(name: 'Com Espaço'), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors'].first).to include('letras minúsculas')
  end

  it 'não deixa usar número de outra conta' do
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox

    post base, params: payload.merge(inbox_ids: [other.id]), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'barra atendente' do
    post base, params: payload, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
