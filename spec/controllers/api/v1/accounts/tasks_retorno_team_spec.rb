require 'rails_helper'

# 🔁 item 343 (13/10) "Retornos para a equipe dos retornos": a Vaneide marca o
# retorno e ele NÃO fica no nome dela; as duas da equipe veem os cards de
# retorno, quem pegar primeiro assume. A equipe é escolhida só pelo admin.
RSpec.describe 'Tasks — equipe dos retornos (item 343)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Gui') }
  let(:vaneide) { create(:user, account: account, role: :agent, name: 'Vaneide') }
  let(:natalia) { create(:user, account: account, role: :agent, name: 'Natália') }
  let(:elizangela) { create(:user, account: account, role: :agent, name: 'Elizangela') }
  let(:base) { "/api/v1/accounts/#{account.id}/tasks" }
  let(:due) { 2.days.from_now.change(hour: 10).iso8601 }
  let!(:settings) do
    tree = [vaneide, natalia, elizangela].to_h { |u| [u.id.to_s, { 'tarefas' => 'edit', 'agenda' => 'edit' }] }
    CrmSetting.create!(account: account, agent_permissions: { 'tree' => tree },
                       agenda_config: { 'retorno_team_user_ids' => [natalia.id, elizangela.id] })
  end

  # card de passagem de um paciente de retorno (o robô abre em nome do admin, sem dono)
  let!(:team_card) do
    Task.create!(account: account, creator: admin, title: '🙋 Atendimento · Rosa — quer remarcar', task_type: 'pos_op',
                 modality: 'retorno', status: :todo)
  end

  it 'retorno marcado na Agenda não fica no nome de quem marcou; avaliação continua', :aggregate_failures do
    post base, params: { title: 'Consulta: Rosa', phone: '11988887777', task_type: 'consulta', modality: 'retorno',
                         unit: 'tatuape', due_at: due }, headers: vaneide.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['assignee']).to be_nil

    post base, params: { title: 'Consulta: Ana', phone: '11977776666', task_type: 'consulta', modality: 'avaliacao',
                         unit: 'tatuape', due_at: due }, headers: vaneide.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('assignee', 'id')).to eq(vaneide.id)
  end

  it 'as duas da equipe veem o card do retorno (marcado como delas) e quem pegar assume; fora da equipe não vê', :aggregate_failures do
    get base, headers: natalia.create_new_auth_token, as: :json
    row = response.parsed_body.find { |t| t['id'] == team_card.id }
    expect(row).to include('retorno_team' => true)

    get "#{base}/alert_count", headers: elizangela.create_new_auth_token, as: :json
    expect(response.parsed_body['count']).to eq(1)

    get base, headers: vaneide.create_new_auth_token, as: :json
    expect(response.parsed_body.pluck('id')).not_to include(team_card.id)

    put "#{base}/#{team_card.id}", params: { assignee_id: elizangela.id, status: 'doing' },
                                   headers: elizangela.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(team_card.reload.assignee).to eq(elizangela)

    # assumido pela Elizangela, a Natália continua vendo ("as duas veem tudo")
    get base, headers: natalia.create_new_auth_token, as: :json
    expect(response.parsed_body.pluck('id')).to include(team_card.id)
  end

  describe 'configuração (Agenda → Conferência do dia)' do
    let(:url) { "/api/v1/accounts/#{account.id}/crm/settings/update_agenda" }

    it 'o admin escolhe a equipe (só gente da conta); devolve na resposta', :aggregate_failures do
      post url, params: { retorno_team_user_ids: [vaneide.id, 999_999] }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['retorno_team_user_ids']).to eq([vaneide.id])
      expect(settings.reload.agenda_config['retorno_team_user_ids']).to eq([vaneide.id])
    end

    it 'responsável da Confirmação de consulta não mexe no interruptor geral' do
      settings.update!(agenda_config: settings.agenda_config.merge('appointment_confirmation' => { 'enabled' => false }))
      post url, params: { appointment_confirmation: { task_assignee_id: 'retorno_team' } }, headers: admin.create_new_auth_token, as: :json
      expect(settings.reload.agenda_config['appointment_confirmation']).to eq('enabled' => false, 'task_assignee_id' => 'retorno_team')
    end
  end
end
