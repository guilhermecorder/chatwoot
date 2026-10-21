require 'rails_helper'

# item 281: quem está ligando — coluna do CRM, caixa de origem e consultas
RSpec.describe Crm::Calls::PatientContext do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Paulista') }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil principal') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', color: '#0EA5E9', position: 1) }

  def consulta(due_at, attrs = {})
    Task.create!({ account: account, creator: agent, contact: contact, title: 'Consulta', task_type: 'consulta',
                   due_at: due_at }.merge(attrs))
  end

  it 'devolve a coluna do CRM, a caixa de origem e a última/próxima consulta' do
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage)
    create(:conversation, account: account, inbox: inbox, contact: contact)
    consulta(10.days.ago, attendance: 'attended')
    consulta(3.days.from_now, canceled_at: Time.current)
    upcoming = consulta(5.days.from_now)

    context = described_class.for_contact(account, contact.id)

    expect(context[:cards]).to contain_exactly(
      hash_including(stage_name: 'Agendamento de Consulta', stage_color: '#0EA5E9', pipeline_name: 'Funil principal')
    )
    expect(context[:origin_inbox]).to eq(id: inbox.id, name: 'WhatsApp Paulista')
    expect(context[:last_appointment]).to include(attendance: 'attended')
    expect(context[:next_appointment]).to include(id: upcoming.id)
  end

  it 'quem nunca passou pelo CRM volta vazio, sem erro' do
    context = described_class.for_contact(account, contact.id)

    expect(context[:cards]).to eq([])
    expect(context[:origin_inbox]).to be_nil
    expect(context[:last_appointment]).to be_nil
  end

  it 'entra no JSON da chamada, menos no card da conversa' do
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage)
    call = Crm::Call.create!(account: account, inbox: inbox, contact: contact, meta_call_id: 'wacid.281',
                             wa_id: '5511999990000', started_at: Time.current)

    expect(call.to_payload[:crm][:cards].first[:stage_name]).to eq('Agendamento de Consulta')
    expect(Crm::Call.payloads([call], account).first[:crm][:cards].size).to eq(1)
    expect(call.to_payload(crm: false)).not_to have_key(:crm)
  end
end
