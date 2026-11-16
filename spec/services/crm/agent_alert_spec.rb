require 'rails_helper'

# 🔧 rodada 192: aviso no Meu Painel quando um atendente de IA remarca/cancela
RSpec.describe Crm::AgentAlert do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assignee) { create(:user, account: account, role: :agent, name: 'Vaneide') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:due_at) { Crm::AgendaSlots::TZ.parse('2026-09-26 10:00') } # sábado
  let(:task) do
    account.tasks.create!(title: 'Consulta: Maísa Teste', task_type: 'consulta', due_at: due_at, unit: 'tatuape',
                          phone: '+5511988887777', creator: admin, assignee: assignee)
  end

  it 'grava o aviso na lista do Radar, direcionado a quem cuida da consulta', :aggregate_failures do
    alert = described_class.push(account: account, kind: 'agente_remarcou', task: task, conversation: conversation, agent_key: 'atendente_pos')
    expect(alert).to include('kind' => 'agente_remarcou', 'task_id' => task.id, 'conversation_id' => conversation.display_id,
                             'contact_name' => 'Maísa Teste', 'phone' => '+5511988887777', 'user_id' => assignee.id, 'user_name' => 'Vaneide',
                             'stage_name' => 'Consulta remarcada', 'acao' => 'Conferir na Agenda')
    expect(alert['motivo']).to eq('O Atendente Pós-agendamento remarcou a consulta de Maísa Teste para sáb 26/09 10:00 · Tatuapé')

    saved = CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts')
    expect(saved.size).to eq(1)

    described_class.push(account: account, kind: 'agente_remarcou', task: task, conversation: conversation, agent_key: 'atendente_pos')
    expect(CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts').size).to eq(1) # mesma consulta = substitui
  end

  it 'cancelamento tem texto próprio e o kind é reconhecido pelo Radar', :aggregate_failures do
    alert = described_class.push(account: account, kind: 'agente_cancelou', task: task, conversation: conversation, agent_key: 'atendente_pos')
    expect(alert['motivo']).to include('cancelou a consulta de Maísa Teste que era sáb 26/09 10:00')
    expect(alert['stage_name']).to eq('Consulta cancelada')
    expect(Crm::RadarExtraAlerts.extra?(alert)).to be(true)
    expect(Crm::RadarExtraAlerts.still_open?(account, alert)).to be(true)
  end

  it 'ainda vale por 24 h e enquanto a consulta existir', :aggregate_failures do
    alert = described_class.push(account: account, kind: 'agente_remarcou', task: task, conversation: conversation, agent_key: 'atendente_pos')
    expect(described_class.still_open?(account, alert)).to be(true)
    expect(described_class.still_open?(account, alert.merge('created_at' => 25.hours.ago.iso8601))).to be(false)
    task.destroy!
    expect(described_class.still_open?(account, alert)).to be(false)
  end

  it 'kind desconhecido não grava nem explode' do
    expect(described_class.push(account: account, kind: 'agente_voou', task: task, conversation: conversation, agent_key: 'atendente_pos')).to be_nil
  end

  describe 'aviso de "pediu atenção" sai quando a equipe fala com a pessoa (16/11/2026)' do
    let(:alert) do
      described_class.push(account: account, kind: 'atendimento_atencao', task: task, conversation: conversation,
                           agent_key: 'atendente_agendamento')
    end

    it 'continua aberto enquanto ninguém da equipe escreveu (cliente e robô não contam)' do
      alert
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
      robot = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
      robot.update!(sender: nil)
      expect(described_class.still_open?(account, alert)).to be(true)
    end

    it 'sai quando alguém da equipe responde depois do aviso' do
      alert
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: assignee)
      expect(described_class.still_open?(account, alert)).to be(false)
    end

    it 'nota interna não conta como conversar com a pessoa' do
      alert
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: assignee,
                       private: true)
      expect(described_class.still_open?(account, alert)).to be(true)
    end

    it 'resposta de ANTES do aviso não destrava' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: assignee,
                       created_at: 2.hours.ago)
      expect(described_class.still_open?(account, alert)).to be(true)
    end

    it 'sai quando a tarefa é concluída' do
      alert
      task.update!(status: :done)
      expect(described_class.still_open?(account, alert)).to be(false)
    end

    it 'aviso de consulta remarcada segue a regra antiga (resposta não tira)' do
      remarcou = described_class.push(account: account, kind: 'agente_remarcou', task: task, conversation: conversation,
                                      agent_key: 'atendente_pos')
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: assignee)
      expect(described_class.still_open?(account, remarcou)).to be(true)
    end
  end
end
