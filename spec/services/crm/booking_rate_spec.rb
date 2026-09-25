require 'rails_helper'

# 📊 item 233 (25/09): taxa de agendamento oficial = mudança de coluna para
# "Agendamento de Consulta" no CRM (qualquer coluna anterior conta)
RSpec.describe Crm::BookingRate do
  let(:account) { create(:account) }
  let!(:pipeline) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0).tap do |p|
      p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
      p.stages.create!(name: 'Envio de Orçamento', color: '#000', position: 1)
      p.stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 2)
      p.stages.create!(name: 'Desmarcou a Consulta', color: '#000', position: 3)
      p.stages.create!(name: 'Pós Operatório', color: '#000', position: 4)
    end
  end
  let(:stages) { pipeline.stages.order(:position).to_a }
  let(:since) { 1.day.ago }
  let(:until_at) { 1.day.from_now }

  def card_for(contact, stage)
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage)
  end

  it 'acha a coluna de agendamento pelo nome (sem pós/desmarcou) quando nada está configurado' do
    expect(described_class.stage(account).name).to eq('Agendamento de Consulta')
  end

  it 'conta quem ENTROU na coluna no período, uma vez por paciente, venha de orçamento ou direto de Novos Contatos', :aggregate_failures do
    via_budget = card_for(create(:contact, account: account), stages[0])
    via_budget.update!(stage_id: stages[1].id)
    via_budget.update!(stage_id: stages[2].id)
    direct = card_for(create(:contact, account: account), stages[0])
    direct.update!(stage_id: stages[2].id)
    direct.update!(stage_id: stages[3].id) # desmarcou depois: a entrada continua contando
    direct.update!(stage_id: stages[2].id) # voltou: NÃO conta de novo (paciente distinto)
    card_for(create(:contact, account: account), stages[1]) # parou no orçamento
    Task.create!(account: account, title: 'Exame: alguém', task_type: 'consulta', modality: 'exames', due_at: 2.days.from_now,
                 creator: create(:user, account: account)) # consulta na Agenda não entra na taxa

    expect(described_class.count(account, since, until_at)).to eq(2)
    expect(described_class.entries(account, since, until_at).count).to eq(3)
  end

  it 'entrada fora do período fica de fora' do
    card = card_for(create(:contact, account: account), stages[0])
    card.update!(stage_id: stages[2].id)
    Crm::StageLog.where(crm_contact_id: card.id, stage_id: stages[2].id).update_all(entered_at: 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.count(account, since, until_at)).to eq(0)
  end

  it 'usa a coluna configurada nos efeitos do agendamento quando existe' do
    CrmSetting.create!(account: account, agenda_config: { 'booking' => { 'stage_id' => stages[3].id } })
    expect(described_class.stage(account).name).to eq('Desmarcou a Consulta')
  end
end
