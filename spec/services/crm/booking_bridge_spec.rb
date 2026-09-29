require 'rails_helper'

# item 285: a ponte entre "entraram na coluna" e "marcadas na Agenda"
RSpec.describe Crm::BookingBridge do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 1) }
  let!(:novos) { Crm::Stage.create!(pipeline: pipeline, name: 'Novos Contatos', position: 1) }
  let!(:agendamento) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 2, color: '#0EA5E9') }
  let!(:cirurgia) { Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Realizada', position: 3) }
  let(:since) { 1.day.ago.beginning_of_day }
  let(:until_at) { Time.current.end_of_day }

  def patient(name)
    create(:contact, account: account, name: name, phone_number: "+55119#{rand(10_000_000..99_999_999)}")
  end

  def card(contact, stage)
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage)
  end

  def consulta(contact, created_at: Time.current, **attrs)
    Task.create!({ account: account, creator: agent, contact: contact, title: "Consulta: #{contact&.name || 'avulsa'}",
                   task_type: 'consulta', due_at: 3.days.from_now, created_at: created_at }.merge(attrs))
  end

  it 'explica cada marcada e cada entrada na coluna, um ramo para cada' do # rubocop:disable RSpec/MultipleExpectations
    ana = patient('Ana') # entrou na coluna e marcou: os dois
    card(ana, novos).update!(stage: agendamento)
    consulta(ana)

    bia = patient('Bia') # entrou na coluna, ninguém marcou
    card(bia, novos).update!(stage: agendamento)

    caio = patient('Caio') # paciente de cirurgia marcou retorno: nunca passou pela coluna
    card(caio, cirurgia)
    consulta(caio)

    dani = patient('Dani') # passou pela coluna há 10 dias, consulta marcada só agora
    dani_card = card(dani, novos)
    dani_card.update!(stage: agendamento)
    dani_card.stage_logs.where(stage_id: agendamento.id).update_all(entered_at: 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
    consulta(dani)

    consulta(patient('Edu')) # sem card
    consulta(nil, phone: nil) # sem cadastro
    consulta(patient('Lançada'), booking_kind: 'registro') # lançamento não é marcada

    bridge = described_class.new(account).call(since, until_at)

    expect(bridge[:column_total]).to eq(2)
    expect(bridge[:agenda_total]).to eq(5)
    expect(bridge[:both_patients]).to eq(1)
    expect(bridge[:agenda].to_h { |b| [b[:key], b[:count]] }).to eq(
      'both' => 1, 'entered_before' => 1, 'other_stage' => 1, 'no_card' => 1, 'no_contact' => 1
    )
    expect(bridge[:agenda].sum { |b| b[:count] }).to eq(bridge[:agenda_total])
    expect(bridge[:column].to_h { |b| [b[:key], b[:count]] }).to eq('both' => 1, 'no_consult' => 1)
    other = bridge[:agenda].find { |b| b[:key] == 'other_stage' }
    expect(other[:stages]).to eq([{ name: 'Cirurgia Realizada', color: cirurgia.color, count: 1 }])
    expect(other[:people].first).to include(name: 'Caio', stage_now: 'Cirurgia Realizada')
  end

  it 'sem coluna de agendamento configurada não quebra' do
    expect(described_class.new(create(:account)).call(since, until_at)).to be_nil
  end
end
