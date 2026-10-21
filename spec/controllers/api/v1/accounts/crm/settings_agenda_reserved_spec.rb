require 'rails_helper'

# 🗂️ item 307: Configurações da agenda — faixa com "serve para", regras para a IA e a prévia do que ela recebe
RSpec.describe 'CRM settings — faixas reservadas e regras da agenda para a IA', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }
  let(:windows) do
    [{ dow: 3, unit: 'paulista', doctor: 'Dr. Henrique Gemelli', turno: 'Tarde', start: '13:00', end: '14:00', block: 15,
       only: %w[pos_op inventado] },
     { dow: 3, unit: 'paulista', doctor: 'Dr. Henrique Gemelli', turno: 'Tarde', start: '14:00', end: '17:00', block: 15, only: [] }]
  end

  it 'salva o "serve para" só com tipos válidos e sem `only` quando a faixa aceita tudo', :aggregate_failures do
    post "#{base}/update_agenda", params: { windows: windows }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    saved = CrmSetting.find_by(account: account).agenda_config['windows']
    expect(saved.first).to include('start' => '13:00', 'only' => ['pos_op'])
    expect(saved.last).not_to have_key('only')
    expect(response.parsed_body['agenda_windows'].first['only']).to eq(['pos_op'])
  end

  it 'salva as regras da clínica e a prévia mostra o que a IA recebe', :aggregate_failures do
    post "#{base}/update_agenda", params: { windows: windows, ai_rules: '  Não oferecer encaixe no mesmo dia.  ' },
                                  headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['agenda_ai_rules']).to eq('Não oferecer encaixe no mesmo dia.')

    get "#{base}/agenda_ai_preview", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['rules']).to include('quarta 13:00–14:00').and include('Não oferecer encaixe no mesmo dia.')
    expect(body['slots']).to be_a(String)
  end

  it 'quem não tem acesso às configurações não mexe nas faixas nem vê a prévia', :aggregate_failures do
    post "#{base}/update_agenda", params: { windows: windows }, headers: agent_user.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:ok)
    get "#{base}/agenda_ai_preview", headers: agent_user.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:ok)
  end
end
