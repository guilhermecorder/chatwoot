require 'rails_helper'

# 🗑️ item 304: "Excluir" um agendamento = Lixeira (fica no banco, com quem e quando);
# restaurar volta; apagar de vez só o admin; card de tarefa comum continua apagando
RSpec.describe 'Tasks trash', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent, name: 'Nat') }
  let(:base) { "/api/v1/accounts/#{account.id}/tasks" }
  let(:appointment) do
    Task.create!(account: account, creator: admin, assignee: admin, title: 'Consulta: Maria', task_type: 'consulta',
                 unit: 'tatuape', modality: 'retorno', due_at: 1.day.from_now)
  end
  let(:card) { Task.create!(account: account, creator: admin, assignee: admin, title: 'Ligar para o laboratório') }

  it 'excluir um agendamento manda para a Lixeira com quem e quando, sem apagar', :aggregate_failures do
    delete "#{base}/#{appointment.id}", headers: agent_user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['canceled_at']).to be_present
    expect(body['canceled_by']).to eq('id' => agent_user.id, 'name' => 'Nat')
    expect(body['cancel_reason']).to eq('excluida_agenda')
    expect(Task.exists?(appointment.id)).to be(true)
  end

  it 'restaurar limpa o rastro e a consulta volta para a grade', :aggregate_failures do
    appointment.to_trash!(by: agent_user)
    put "#{base}/#{appointment.id}", params: { canceled: false }, headers: agent_user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    appointment.reload
    expect(appointment.canceled_at).to be_nil
    expect(appointment.canceled_by).to be_nil
    expect(appointment.cancel_reason).to be_nil
  end

  it 'cancelar pela ficha também guarda quem cancelou' do
    put "#{base}/#{appointment.id}", params: { canceled: true }, headers: agent_user.create_new_auth_token, as: :json
    expect(appointment.reload).to have_attributes(canceled_by: agent_user, cancel_reason: 'cancelada_equipe')
  end

  it 'apagar de vez: admin pode (force), equipe não', :aggregate_failures do
    appointment.to_trash!(by: agent_user)
    delete "#{base}/#{appointment.id}", params: { force: 1 }, headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(Task.exists?(appointment.id)).to be(true)

    delete "#{base}/#{appointment.id}", params: { force: 1 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(Task.exists?(appointment.id)).to be(false)
  end

  it 'card de tarefa comum continua sendo apagado de verdade' do
    delete "#{base}/#{card.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(Task.exists?(card.id)).to be(false)
  end

  it 'a Agenda continua recebendo o agendamento da Lixeira (para listar e restaurar)' do
    appointment.to_trash!(by: agent_user)
    get base, headers: admin.create_new_auth_token, as: :json
    row = response.parsed_body.find { |t| t['id'] == appointment.id }
    expect(row['canceled_by']['name']).to eq('Nat')
  end
end
