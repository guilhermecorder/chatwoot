require 'rails_helper'

# 🩺 item 251 (26/09): Atendente de Pós-operatório — tarefa para a equipe, dono pela Agenda, chamar humano
RSpec.describe Crm::HandoffTask do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:vaneide) { create(:user, account: account, role: :agent, name: 'Vaneide') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Carlos Operado', phone_number: '+5511999990100') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:agent_cfg) do
    { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id], 'task_assignee_id' => vaneide.id, 'recent_surgery_days' => 60 }
  end
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_pos_op' => agent_cfg } })
  end

  it 'abre a tarefa (tipo pos_op, aparece no Meu Painel) para a pessoa escolhida no card e deixa a nota', :aggregate_failures do
    out = described_class.open!(account: account, contact: contact, conversation: conversation, agent_key: 'atendente_pos_op',
                                motivo: 'acabou o colírio antes do retorno', detalhes: 'paciente disse que o frasco acabou', urgencia: 'normal')
    task = out[:task]
    expect(out[:created]).to be(true)
    expect(task.task_type).to eq('pos_op')
    expect(task.assignee).to eq(vaneide)
    expect(task.priority).to eq('high')
    expect(task.title).to eq('🩺 Pós-op · Carlos Operado — acabou o colírio antes do retorno')
    expect(task.description).to include('paciente disse que o frasco acabou', "Conversa ##{conversation.display_id}")
    note = conversation.messages.where(message_type: :activity, private: true).last
    expect(note.content).to include('abriu a tarefa', 'Vaneide')
    # entra na lista "tarefas esperando você" (consulta/cirurgia ficam fora; pos_op entra)
    expect(account.tasks.where(assignee_id: vaneide.id, status: %w[todo doing]).where.not(task_type: %w[consulta cirurgia])).to include(task)
  end

  it 'segunda chamada do mesmo paciente só complementa a tarefa aberta; urgência alta vira urgente + aviso no Radar', :aggregate_failures do
    first = described_class.open!(account: account, contact: contact, conversation: conversation, agent_key: 'atendente_pos_op',
                                  motivo: 'dúvida do caso', urgencia: 'normal')[:task]
    out = described_class.open!(account: account, contact: contact, conversation: conversation, agent_key: 'atendente_pos_op',
                                motivo: 'dor forte no olho direito', urgencia: 'alta')
    expect(out[:created]).to be(false)
    expect(out[:task].id).to eq(first.id)
    expect(first.reload.priority).to eq('urgent')
    expect(first.description).to include('dúvida do caso', 'dor forte no olho direito')
    alerts = settings.reload.ai_config.dig('opportunity_state', 'alerts')
    expect(alerts.last).to include('kind' => 'pos_op_atencao', 'task_id' => first.id, 'user_id' => vaneide.id)
  end

  it 'sem pessoa escolhida, cai em quem cuida da coluna / conferência de cirurgia' do
    settings.update!(ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_pos_op' => agent_cfg.except('task_assignee_id') } },
                     agenda_config: { 'attendance_owners' => { 'cirurgia_user_id' => vaneide.id } })
    task = described_class.open!(account: account, contact: contact, conversation: conversation, agent_key: 'atendente_pos_op',
                                 motivo: 'pediu atestado', urgencia: 'normal')[:task]
    expect(task.assignee).to eq(vaneide)
  end

  describe 'ferramenta abrir_tarefa (Crm::ResponderTools)' do
    it 'em sombra só simula; ao vivo cria e registra a ação', :aggregate_failures do
      shadow = Crm::ResponderTools.new(conversation: conversation, agent_key: 'atendente_pos_op', live: false)
      expect(shadow.call('abrir_tarefa', 'motivo' => 'x', 'urgencia' => 'alta')).to include(simulado: true, ok: true)
      expect(account.tasks.where(task_type: 'pos_op')).to be_empty

      live = Crm::ResponderTools.new(conversation: conversation, agent_key: 'atendente_pos_op', live: true)
      result = live.call('abrir_tarefa', 'motivo' => 'perdeu a receita', 'detalhes' => 'quer a foto da receita', 'urgencia' => 'normal')
      expect(result).to include(ok: true, criada: true, responsavel: 'Vaneide')
      expect(live.acoes.last['resumo']).to include('abriu tarefa', 'perdeu a receita')
      expect(live.definitions.map { |d| d[:name] }).to include('abrir_tarefa')
    end

    it 'os outros atendentes não recebem a ferramenta' do
      tools = Crm::ResponderTools.new(conversation: conversation, agent_key: 'atendente_pos', live: true)
      expect(tools.definitions.map { |d| d[:name] }).not_to include('abrir_tarefa')
      expect(tools.call('abrir_tarefa', 'motivo' => 'x', 'urgencia' => 'alta')[:ok]).to be(false)
    end
  end

  describe 'quem é o dono da conversa (CrmListener) e chamar humano no job' do
    let(:listener) { CrmListener.instance }

    before { stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true) }

    it 'paciente com cirurgia realizada há 10 dias na Agenda vai para o Pós-operatório mesmo sem card na coluna', :aggregate_failures do
      account.tasks.create!(title: 'Cirurgia: Carlos Operado', task_type: 'cirurgia', creator: admin, contact: contact,
                            due_at: 10.days.ago, status: :done, attendance: 'attended')
      agents = { 'atendente_pos_op' => agent_cfg }
      expect(listener.send(:responder_owner_for, conversation, agents)).to eq('atendente_pos_op')

      other = create(:contact, account: account, name: 'Sem Cirurgia', phone_number: '+5511999990101')
      other_conv = create(:conversation, account: account, inbox: inbox, contact: other)
      expect(listener.send(:responder_owner_for, other_conv, agents)).to be_nil
    end

    it 'ao vivo, chamar_humano no pós-op deixa a tarefa urgente mesmo sem a IA usar a ferramenta', :aggregate_failures do
      incoming = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'estou com muita dor')
      result = { mensagens: ['Procure um pronto atendimento oftalmológico agora.', 'Equipe: (11) 98769-0286.'], etapa: 'pos_cirurgico',
                 agendar: false, agendamento: {}, cancelar: false, pausar: false, chamar_humano: true,
                 leitura: 'Dor forte no pós-op: sintoma de alerta.', acoes: [] }
      service = instance_double(Crm::ResponderAgentService, call: result)
      allow(Crm::ResponderAgentService).to receive(:new).and_return(service)
      allow(Crm::MediaReadingService).to receive(:read_pending!).and_return({})

      Crm::ResponderAgentJob.perform_now(conversation.id, incoming.id, 'atendente_pos_op')

      task = account.tasks.find_by(task_type: 'pos_op')
      expect(task).to be_present
      expect(task.priority).to eq('urgent')
      expect(task.title).to include('Dor forte no pós-op')
      expect(conversation.reload.additional_attributes.dig('cevico_atendente_wa', 'paused')).to be(true)
      expect(conversation.messages.where(message_type: :outgoing).count).to eq(2)
    end
  end
end
