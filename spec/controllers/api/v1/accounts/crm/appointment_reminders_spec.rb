require 'rails_helper'

# 🖐️ item 320: envio manual do lembrete de confirmação pelo card
RSpec.describe 'CEVICO Appointment Reminders API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/appointment_reminders/run" }

  it 'devolve o motivo quando o lembrete não existe', :aggregate_failures do
    post base, params: { regua: 'd2' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/não encontrado/)
  end

  it 'roda o lembrete ligado e devolve a contagem e o estado', :aggregate_failures do
    inbox = create(:inbox, account: account)
    rule = { 'enabled' => true, 'hour' => 10, 'inbox_id' => inbox.id, 'mode' => 'live',
             'template_params' => { 'name' => 'confirma', 'language' => 'pt_BR', 'processed_params' => { 'body' => {} } } }
    CrmSetting.create!(account: account, agenda_config: { 'appointment_reminders' => { 'd2' => rule } })

    post base, params: { regua: 'd2' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('ok' => true, 'sent' => 0, 'skipped' => 0)
    expect(response.parsed_body['state']['d2']).to include('mode' => 'live')
  end

  it 'barra atendente sem a concessão de Configurações' do
    post base, params: { regua: 'd2' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
