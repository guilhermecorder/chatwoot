require 'rails_helper'

# 🎨 item 290: a Agenda salva a cor do agendamento pelo controlador de tarefas
RSpec.describe 'Tasks color', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/tasks" }
  let(:task) do
    Task.create!(account: account, creator: admin, assignee: admin, title: 'Maria', task_type: 'consulta',
                 unit: 'tatuape', due_at: 1.day.from_now)
  end

  it 'salva a cor e devolve no JSON', :aggregate_failures do
    put "#{base}/#{task.id}", params: { color: '#16A34A' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['color']).to eq('#16A34A')
    expect(task.reload.color).to eq('#16A34A')
  end

  it 'vale para a equipe toda: agente comum pinta a consulta da unidade', :aggregate_failures do
    put "#{base}/#{task.id}", params: { color: '#2563EB' }, headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.color).to eq('#2563EB')

    get base, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.find { |t| t['id'] == task.id }['color']).to eq('#2563EB')
  end

  it 'aceita minúsculas e guarda como na lista' do
    put "#{base}/#{task.id}", params: { color: '#dc2626' }, headers: admin.create_new_auth_token, as: :json
    expect(task.reload.color).to eq('#DC2626')
  end

  it '"Padrão" (nulo ou vazio) tira a cor', :aggregate_failures do
    task.update!(color: '#DC2626')
    put "#{base}/#{task.id}", params: { color: nil }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.color).to be_nil

    task.update!(color: '#DC2626')
    put "#{base}/#{task.id}", params: { color: '' }, headers: admin.create_new_auth_token, as: :json
    expect(task.reload.color).to be_nil
  end

  it 'recusa cor fora da lista e não muda nada', :aggregate_failures do
    task.update!(color: '#DC2626')
    put "#{base}/#{task.id}", params: { color: '#123456' }, headers: admin.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:ok)
    expect(task.reload.color).to eq('#DC2626')
  end

  it 'pintar não mexe na presença, na situação nem no contador de remarcação', :aggregate_failures do
    task.update!(attendance: 'missed')
    put "#{base}/#{task.id}", params: { color: '#7C3AED' }, headers: admin.create_new_auth_token, as: :json
    task.reload
    expect(task.attendance).to eq('missed')
    expect(task.status).to eq('todo')
    expect(task.rescheduled_count).to eq(0)
    expect(task.canceled_at).to be_nil
  end

  it 'marcar presença não mexe na cor', :aggregate_failures do
    task.update!(color: '#7C3AED')
    put "#{base}/#{task.id}", params: { attendance: 'attended', status: 'done' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.color).to eq('#7C3AED')
    expect(task.attendance).to eq('attended')
  end

  it 'cria já com cor' do
    post base, params: { title: 'João', task_type: 'consulta', unit: 'tatuape', due_at: 2.days.from_now.iso8601, color: '#EA580C' },
               headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['color']).to eq('#EA580C')
  end
end
