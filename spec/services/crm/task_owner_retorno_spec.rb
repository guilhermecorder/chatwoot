require 'rails_helper'
require 'rake'

# 🔁 item 343 (13/10) "Retornos para a equipe dos retornos": retorno não tem
# dono individual — a Natália e a Elizangela (a equipe escolhida pelo admin)
# veem tudo e quem pegar primeiro assume. Sem equipe escolhida, nada muda.
RSpec.describe Crm::TaskOwner do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let(:vaneide) { create(:user, account: account, role: :agent, name: 'Vaneide') }
  let(:natalia) { create(:user, account: account, role: :agent, name: 'Natália') }
  let(:elizangela) { create(:user, account: account, role: :agent, name: 'Elizangela') }
  let(:contact) { create(:contact, account: account, name: 'Rosa Retorno', phone_number: '+5511999990343') }
  let!(:settings) do
    owners = { 'consulta_user_id' => vaneide.id, 'cirurgia_user_id' => vaneide.id }
    CrmSetting.create!(account: account, agenda_config: { 'attendance_owners' => owners })
  end

  before { admin } # o robô cria em nome do primeiro administrador

  def team!
    settings.update!(agenda_config: settings.agenda_config.merge('retorno_team_user_ids' => [natalia.id, elizangela.id]))
  end

  def consulta(attrs = {})
    Task.create!({ account: account, creator: vaneide, assignee: vaneide, title: 'Consulta: Rosa', task_type: 'consulta',
                   unit: 'tatuape', contact: contact, due_at: 2.days.from_now }.merge(attrs))
  end

  describe '.retorno?' do
    it 'reconhece o tipo retorno, o procedimento escrito "Retorno" e deixa de fora pós-op, exame e cirurgia', :aggregate_failures do
      expect(described_class.retorno?(task_type: 'consulta', modality: 'retorno')).to be(true)
      expect(described_class.retorno?('task_type' => 'consulta', 'procedure' => 'Retorno 30 dias')).to be(true)
      expect(described_class.retorno?(task_type: 'consulta', modality: 'avaliacao', procedure: 'retorno')).to be(true)
      expect(described_class.retorno?(task_type: 'consulta', procedure: 'Retorno pós-op')).to be(false)
      expect(described_class.retorno?(task_type: 'consulta', modality: 'pos_op', procedure: 'retorno')).to be(false)
      expect(described_class.retorno?(task_type: 'cirurgia', procedure: 'Retorno')).to be(false)
      expect(described_class.retorno?(task_type: 'consulta', modality: 'avaliacao')).to be(false)
      expect(described_class.retorno?(nil)).to be(false)
      expect(described_class.retorno?(Task.new(task_type: 'consulta', modality: 'retorno'))).to be(true)
    end
  end

  describe '.resolve' do
    it 'retorno com a equipe configurada = sem dono; sem equipe = como antes', :aggregate_failures do
      expect(described_class.resolve(account, contact: contact, task_type: 'consulta', retorno: true)).to eq(vaneide)
      team!
      expect(described_class.resolve(account, contact: contact, task_type: 'consulta', retorno: true)).to be_nil
      expect(described_class.resolve(account, contact: contact, task_type: 'consulta')).to eq(vaneide)
    end

    it 'a equipe só conta quem ainda é da conta' do
      settings.update!(agenda_config: { 'retorno_team_user_ids' => [999_999] })
      expect(described_class.retorno_team?(account)).to be(false)
    end
  end

  describe 'agendamento novo (Task antes de criar)' do
    it 'retorno nasce sem dono quando há equipe; avaliação e cirurgia continuam com quem marcou', :aggregate_failures do
      team!
      expect(consulta(modality: 'retorno').assignee).to be_nil
      expect(consulta(modality: 'avaliacao', due_at: 3.days.from_now).assignee).to eq(vaneide)
      expect(consulta(task_type: 'cirurgia', title: 'Cirurgia: Rosa', due_at: 4.days.from_now).assignee).to eq(vaneide)
    end

    it 'retorno descoberto pelo histórico (IA marca sem tipo) também nasce sem dono' do
      consulta(modality: 'avaliacao', due_at: 10.days.ago)
      team!
      task = consulta(modality: nil)
      expect(task).to have_attributes(modality: 'retorno', assignee: nil)
    end

    it 'sem equipe escolhida, nada muda' do
      expect(consulta(modality: 'retorno').assignee).to eq(vaneide)
    end
  end

  describe '.patient_retorno?' do
    it 'olha a PRÓXIMA consulta aberta do paciente', :aggregate_failures do
      expect(described_class.patient_retorno?(account, contact)).to be(false)
      consulta(modality: 'retorno')
      expect(described_class.patient_retorno?(account, contact)).to be(true)
      consulta(modality: 'avaliacao', due_at: 1.day.from_now) # a de amanhã vem antes
      expect(described_class.patient_retorno?(account, contact)).to be(false)
    end
  end

  describe 'aviso "disse NÃO" (Crm::AgentAlert)' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'retorno avisa cada pessoa da equipe — não quem marcou', :aggregate_failures do
      task = consulta(modality: 'retorno') # nasceu antes da equipe: ainda no nome da Vaneide
      team!
      Crm::AgentAlert.push(account: account, kind: 'nao_confirmou', task: task, conversation: conversation, agent_key: 'atendente_pos')
      alerts = settings.reload.ai_config.dig('opportunity_state', 'alerts')
      expect(alerts.pluck('user_id')).to contain_exactly(natalia.id, elizangela.id)
      expect(alerts.pluck('task_id').uniq).to eq([task.id])
    end

    it 'avaliação segue para o responsável da consulta' do
      team!
      task = consulta(modality: 'avaliacao')
      Crm::AgentAlert.push(account: account, kind: 'nao_confirmou', task: task, conversation: conversation, agent_key: 'atendente_pos')
      expect(settings.reload.ai_config.dig('opportunity_state', 'alerts').pluck('user_id')).to eq([vaneide.id])
    end
  end

  describe 'rake cevico:retornos_equipe' do
    before do
      Rake::Task.define_task(:environment)
      Rake.application.rake_require('tasks/cevico_retornos_equipe') unless Rake::Task.task_defined?('cevico:retornos_equipe')
      Rake::Task['cevico:retornos_equipe'].reenable
    end

    def run(dry)
      stub_const('ENV', ENV.to_h.merge('ACCOUNT_ID' => account.id.to_s, 'DRY' => dry))
      expect { Rake::Task['cevico:retornos_equipe'].invoke }.to output(/retorno/).to_stdout
    end

    it 'DRY=1 só lista; DRY=0 tira o dono só dos retornos FUTUROS no nome de quem é de fora', :aggregate_failures do
      fora = consulta(modality: 'retorno')
      passado = consulta(modality: 'retorno', due_at: 2.days.ago)
      da_equipe = consulta(modality: 'retorno', assignee: natalia, due_at: 5.days.from_now)
      avaliacao = consulta(modality: 'avaliacao', due_at: 6.days.from_now)
      team!

      run('1')
      expect(fora.reload.assignee).to eq(vaneide)

      Rake::Task['cevico:retornos_equipe'].reenable
      run('0')
      expect(fora.reload.assignee).to be_nil
      expect(passado.reload.assignee).to eq(vaneide)
      expect(da_equipe.reload.assignee).to eq(natalia)
      expect(avaliacao.reload.assignee).to eq(vaneide)
    end
  end
end
