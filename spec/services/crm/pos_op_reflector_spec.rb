require 'rails_helper'

# 🩹 21/10: consulta de pós-op marcada na Agenda → card na coluna "Consulta Pós Op"
RSpec.describe Crm::PosOpReflector do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Mariane Santana', phone_number: '+5511945521682') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage_booked) { pipeline.stages.create!(name: 'Agendamento de Consulta', position: 1) }
  let!(:stage_confirmed) { pipeline.stages.create!(name: 'Consulta Confirmada', position: 2) }
  let!(:stage_postop) { pipeline.stages.create!(name: 'Pós Operatório', position: 8) }
  let!(:stage_postop_visit) { pipeline.stages.create!(name: 'Consulta Pós Op', position: 9) }
  let!(:card) { Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: stage_postop.id) }
  let(:tz) { described_class::TZ }

  before { CrmSetting.create!(account: account, agenda_config: { 'booking' => { 'stage_id' => stage_booked.id } }) }

  def consulta(modality:, due_at: tz.now + 3.days, **extra)
    account.tasks.create!({ title: "Consulta: #{contact.name}", task_type: 'consulta', modality: modality, due_at: due_at,
                            unit: 'paulista', phone: contact.phone_number, contact: contact, creator: admin, status: :todo }.merge(extra))
  end

  it 'acha a coluna pelo nome, com ou sem acento e hífen', :aggregate_failures do
    expect(described_class.pos_op_name?('Consulta Pós Op')).to be(true)
    expect(described_class.pos_op_name?('CONSULTA PÓS-OPERATÓRIO')).to be(true)
    expect(described_class.pos_op_name?('Pós Operatório')).to be(false)
    expect(described_class.stage_for(account)).to eq(stage_postop_visit)
  end

  it 'equipe marca consulta de pós-op na Agenda: o card vai para "Consulta Pós Op" e as automações disparam' do
    allow(CrmAutomationTriggerService).to receive(:new).and_call_original
    expect(CrmAutomationTriggerService).to receive(:new)
      .with(hash_including(event_type: 'card_entered', new_stage: stage_postop_visit)).and_call_original
    consulta(modality: 'pos_op')
    expect(card.reload.stage_id).to eq(stage_postop_visit.id)
  end

  it 'consulta que vira pós-op na edição também leva o card' do
    task = consulta(modality: 'retorno')
    expect(card.reload.stage_id).to eq(stage_postop.id)
    task.update!(modality: 'pos_op')
    expect(card.reload.stage_id).to eq(stage_postop_visit.id)
  end

  it 'paciente sem card: nasce direto na coluna' do
    card.destroy!
    consulta(modality: 'pos_op')
    expect(Crm::Contact.find_by(contact_id: contact.id, pipeline_id: pipeline.id).stage_id).to eq(stage_postop_visit.id)
  end

  it 'consulta comum, cancelada ou no passado não mexe no card', :aggregate_failures do
    consulta(modality: 'avaliacao')
    consulta(modality: 'pos_op', canceled_at: Time.current)
    consulta(modality: 'pos_op', due_at: tz.now - 3.days)
    expect(card.reload.stage_id).to eq(stage_postop.id)
  end

  it 'consulta de parceiro (Oftalmofácil) e o que vem do sync do hub ficam de fora', :aggregate_failures do
    consulta(modality: 'pos_op', origin: 'oftalmofacil')
    consulta(modality: 'pos_op', source: 'oftalmofacil', due_at: tz.now + 4.days)
    expect(card.reload.stage_id).to eq(stage_postop.id)
  end

  it 'sem a coluna no CRM: nada acontece' do
    stage_postop_visit.update!(name: 'Outra coisa')
    consulta(modality: 'pos_op')
    expect(card.reload.stage_id).to eq(stage_postop.id)
  end

  it 'o agendamento do robô não puxa de volta para "Agendamento de Consulta"' do
    consulta(modality: 'pos_op')
    result = Crm::BookingSideEffects.apply(account: account, contact: contact, conversation: nil, outcome: :created)
    expect(result[:stage]).to be_nil
    expect(card.reload.stage_id).to eq(stage_postop_visit.id)
  end

  it 'confirmar a consulta de pós-op não leva para "Consulta Confirmada" (o selo da Agenda continua)', :aggregate_failures do
    task = consulta(modality: 'pos_op')
    task.update!(confirmed_at: Time.current)
    Crm::ConfirmationReflector.call(account: account, task: task)
    expect(card.reload.stage_id).to eq(stage_postop_visit.id)
    expect(task.reload.confirmed_at).to be_present
  end

  it 'consulta comum confirmada segue indo para "Consulta Confirmada"' do
    card.update!(stage_id: stage_booked.id)
    task = consulta(modality: 'avaliacao')
    Crm::ConfirmationReflector.call(account: account, task: task)
    expect(card.reload.stage_id).to eq(stage_confirmed.id)
  end
end
