require 'rails_helper'

# 💰 item 324 (05/10): valor do agendamento — pré-configuração salva na Agenda,
# valores lançados à mão no card (com quem lançou) e o valor que vale no JSON
RSpec.describe 'Tasks price', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Guilherme') }
  let(:agent_user) { create(:user, account: account, role: :agent, name: 'Ana Recepção') }
  let(:base) { "/api/v1/accounts/#{account.id}/tasks" }
  let(:settings) { "/api/v1/accounts/#{account.id}/crm/settings" }
  let(:prices) do
    { avaliacao: '150', retorno: 'sem custo', particular: { 'Dra. Roberta Negri' => '450' }, exames: [{ name: 'Pentacam', price: '350' }] }
  end
  let(:consulta) do
    { title: 'Maria Particular', task_type: 'consulta', modality: 'avaliacao', unit: 'tatuape', doctor: 'Dra. Roberta Negri',
      due_at: 2.days.from_now.iso8601, particular: true }
  end

  before { post "#{settings}/update_agenda", params: { appointment_prices: prices }, headers: admin.create_new_auth_token, as: :json }

  it 'só o admin salva a pré-configuração; ela volta arrumada nas configurações', :aggregate_failures do
    expect(response).to have_http_status(:ok)
    expect(CrmSetting.find_by(account: account).agenda_config['appointment_prices'])
      .to include('avaliacao' => '150,00', 'particular' => { 'Dra. Roberta Negri' => '450,00' })

    post "#{settings}/update_agenda", params: { appointment_prices: { avaliacao: '1' } }, headers: agent_user.create_new_auth_token, as: :json
    expect(CrmSetting.find_by(account: account).agenda_config['appointment_prices']['avaliacao']).to eq('150,00')

    get settings, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['appointment_prices']).to include('avaliacao' => '150,00',
                                                                  'exames' => [{
                                                                    'name' => 'Pentacam', 'price' => '350,00'
                                                                  }])
  end

  it 'consulta particular nasce com o valor do médico; valor lançado à mão vence e guarda quem lançou', :aggregate_failures do
    post base, params: consulta, headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body).to include('particular' => true, 'charges' => [])
    expect(body['price']).to include('text' => '450,00', 'source' => 'particular')

    put "#{base}/#{body['id']}", params: { charges: [{ label: 'Consulta', amount: '500' }, { label: 'Topografia', amount: 'R$ 200' }] },
                                 headers: agent_user.create_new_auth_token, as: :json
    expect(response.parsed_body['price']).to include('text' => '700,00', 'source' => 'manual', 'by' => 'Ana Recepção')
    expect(Task.find(body['id']).charges.pluck('amount', 'by_name')).to eq([['500,00', 'Ana Recepção'], ['200,00', 'Ana Recepção']])

    # outra pessoa salva o card sem mexer nos valores: o nome de quem lançou fica
    put "#{base}/#{body['id']}", params: { charges: [{ label: 'Consulta', amount: '500,00' }, { label: 'Topografia', amount: '200,00' }] },
                                 headers: admin.create_new_auth_token, as: :json
    expect(Task.find(body['id']).charges.pluck('by_name').uniq).to eq(['Ana Recepção'])

    # tirou os valores: volta a valer o pré-configurado
    put "#{base}/#{body['id']}", params: { charges: [] }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['price']).to include('text' => '450,00', 'source' => 'particular')
  end
end
