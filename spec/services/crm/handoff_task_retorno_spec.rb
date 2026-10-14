require 'rails_helper'

# 🔁 item 343 (13/10): a tarefa de passagem dos atendentes de IA e dos
# lembretes recusados — paciente de RETORNO vai para a equipe dos retornos
# (sem dono individual); fora do pós-op, o plano B é o responsável de CONSULTA.
RSpec.describe Crm::HandoffTask do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let(:vaneide) { create(:user, account: account, role: :agent, name: 'Vaneide') }
  let(:cirurgia_owner) { create(:user, account: account, role: :agent, name: 'Cirurgias') }
  let(:natalia) { create(:user, account: account, role: :agent, name: 'Natália') }
  let(:elizangela) { create(:user, account: account, role: :agent, name: 'Elizangela') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Rosa Retorno', phone_number: '+5511999990344') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:agenda) do
    { 'attendance_owners' => { 'consulta_user_id' => vaneide.id, 'cirurgia_user_id' => cirurgia_owner.id } }
  end
  let!(:settings) { CrmSetting.create!(account: account, agenda_config: agenda, ai_config: { 'agents' => {} }) }

  before { admin } # o robô cria em nome do primeiro administrador

  def team!
    settings.update!(agenda_config: settings.agenda_config.merge('retorno_team_user_ids' => [natalia.id, elizangela.id]))
  end

  def retorno_marcado!
    Task.create!(account: account, creator: vaneide, assignee: vaneide, title: 'Consulta: Rosa', task_type: 'consulta',
                 modality: 'retorno', unit: 'tatuape', contact: contact, due_at: 2.days.from_now)
  end

  def open!(agent_key, urgencia: 'normal')
    described_class.open!(account: account, contact: contact, conversation: conversation, agent_key: agent_key,
                          motivo: 'quer remarcar o retorno', urgencia: urgencia)[:task]
  end

  it 'atendente de agendamento sem escolha: responsável da conferência de CONSULTA (não o de cirurgia)' do
    expect(open!('atendente_pos').assignee).to eq(vaneide)
  end

  it 'pós-operatório continua com o responsável de cirurgia' do
    expect(open!('atendente_pos_op').assignee).to eq(cirurgia_owner)
  end

  it 'paciente de retorno: sem dono, carimbada para a equipe, nota e avisos para as duas', :aggregate_failures do
    retorno_marcado!
    team!
    task = open!('atendente_pos', urgencia: 'alta')
    expect(task.assignee).to be_nil
    expect(task.modality).to eq('retorno')
    expect(conversation.messages.where(message_type: :activity).last.content).to include('a equipe dos retornos')
    alerts = settings.reload.ai_config.dig('opportunity_state', 'alerts')
    expect(alerts.select { |a| a['task_id'] == task.id }.pluck('user_id')).to contain_exactly(natalia.id, elizangela.id)
  end

  it 'lembrete recusado de paciente de retorno também vai para a equipe' do
    retorno_marcado!
    team!
    expect(open!('Confirmação de consulta')).to have_attributes(assignee: nil, modality: 'retorno')
  end

  it 'card do agente com "Equipe dos retornos" manda tudo para a equipe; com pessoa escolhida, para ela', :aggregate_failures do
    team!
    settings.update!(ai_config: { 'agents' => { 'atendente_agendamento' => { 'task_assignee_id' => 'retorno_team' } } })
    expect(open!('atendente_agendamento')).to have_attributes(assignee: nil, modality: 'retorno')

    other = create(:contact, account: account, name: 'Outro', phone_number: '+5511999990345')
    settings.update!(agenda_config: settings.agenda_config.merge('appointment_confirmation' => { 'task_assignee_id' => natalia.id.to_s }))
    task = described_class.open!(account: account, contact: other, conversation: nil, agent_key: 'Confirmação de consulta',
                                 motivo: 'lembrete não chegou')[:task]
    expect(task).to have_attributes(assignee: natalia, modality: nil)
  end

  it 'sem equipe configurada, retorno segue o caminho antigo' do
    retorno_marcado!
    expect(open!('atendente_pos')).to have_attributes(assignee: vaneide, modality: nil)
  end
end
