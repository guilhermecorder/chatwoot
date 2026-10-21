require 'rails_helper'

# 🏥 item 300: o formulário da Agenda manda a origem e o "confirmou" à mão
RSpec.describe 'Tasks API — origem e confirmação (item 300)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:due) { 1.day.from_now.change(hour: 12).iso8601 }

  it 'cria com origem: contato nasce com a etiqueta e o retorno traz origin/confirmed_at' do
    post "/api/v1/accounts/#{account.id}/tasks",
         params: { title: 'Joãozinho', phone: '11988887777', task_type: 'consulta', due_at: due, origin: 'oftalmofacil' },
         headers: headers, as: :json
    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body['origin']).to eq('oftalmofacil')
    expect(body['contact_id']).to be_present
    expect(body).to include('confirmed_at' => nil)
    expect(account.contacts.find(body['contact_id']).label_list).to include('of_agenda')
  end

  it 'origem inválida é recusada' do
    post "/api/v1/accounts/#{account.id}/tasks",
         params: { title: 'X', task_type: 'consulta', due_at: due, origin: 'outra' }, headers: headers, as: :json
    expect(response).not_to have_http_status(:created)
  end

  it 'marca e desmarca o confirmou à mão' do
    task = account.tasks.create!(title: 'Ana', task_type: 'consulta', creator: admin, assignee: admin, due_at: due)
    patch "/api/v1/accounts/#{account.id}/tasks/#{task.id}", params: { confirmed: true }, headers: headers, as: :json
    expect(response.parsed_body['confirmed_at']).to be_present
    patch "/api/v1/accounts/#{account.id}/tasks/#{task.id}", params: { confirmed: false }, headers: headers, as: :json
    expect(response.parsed_body['confirmed_at']).to be_nil
  end
end
