require 'rails_helper'

# 🔁 Auditoria 10/2026 (#197): remarcar não puxa o card de volta para
# "Agendamento de Consulta" (nem dispara de novo o "consulta marcada") e
# não conta como agendamento NOVO de quem já tinha agendado. A primeira
# chegada à coluna (card que nunca passou por lá) continua contando.
RSpec.describe Crm::BookingSideEffects do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage_new) { pipeline.stages.create!(name: 'Novos Contatos', position: 0) }
  let!(:stage_booked) { pipeline.stages.create!(name: 'Agendamento de Consulta', position: 1) }
  let!(:stage_confirmed) { pipeline.stages.create!(name: 'Consulta Confirmada', position: 2) }
  let!(:stage_missed) { pipeline.stages.create!(name: 'Não foi à consulta', position: 3) }
  let(:window) { [1.hour.ago, 1.hour.from_now] }

  before do
    CrmSetting.create!(account: account, agenda_config: { 'booking' => { 'stage_id' => stage_booked.id },
                                                          'attendance_stages' => { 'missed_stage_id' => stage_missed.id } })
  end

  def apply(outcome)
    described_class.apply(account: account, contact: contact, conversation: conversation, outcome: outcome)
  end

  def card_in(stage)
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: stage.id)
  end

  it 'card em "Consulta Confirmada" remarca e volta quieto para o agendamento: sem automação, sem contar', :aggregate_failures do
    card = card_in(stage_confirmed)
    allow(CrmAutomationTriggerService).to receive(:new).and_call_original
    expect(CrmAutomationTriggerService).not_to receive(:new).with(hash_including(event_type: 'card_entered'))
    expect(CrmAutomationTriggerService).not_to receive(:new).with(hash_including(event_type: 'card_left'))

    result = apply(:rescheduled)

    expect(result[:stage]).to eq('Agendamento de Consulta')
    expect(result[:labels]).to eq(['consulta_reagendada'])
    expect(card.reload.stage_id).to eq(stage_booked.id)
    expect(card.stage_logs.find_by(stage_id: stage_booked.id).event_type).to eq('rescheduled')
    expect(Crm::BookingRate.count(account, *window)).to eq(0)
  end

  it 'card já em "Consulta Realizada" (depois da confirmação) remarca e fica onde está', :aggregate_failures do
    done = pipeline.stages.create!(name: 'Consulta Realizada', position: 4)
    card = card_in(done)
    allow(CrmAutomationTriggerService).to receive(:new).and_call_original
    expect(CrmAutomationTriggerService).not_to receive(:new).with(hash_including(event_type: 'card_entered'))
    expect(CrmAutomationTriggerService).not_to receive(:new).with(hash_including(event_type: 'card_left'))

    expect(apply(:rescheduled)[:stage]).to be_nil
    expect(card.reload.stage_id).to eq(done.id)
    expect(card.stage_logs.where(stage_id: stage_booked.id)).to be_empty
  end

  it 'quem faltou e remarcou volta para o agendamento, mas a passagem é "rescheduled" e não entra na taxa', :aggregate_failures do
    card = card_in(stage_missed)

    expect(apply(:rescheduled)[:stage]).to eq('Agendamento de Consulta')
    expect(card.reload.stage_id).to eq(stage_booked.id)
    expect(card.stage_logs.find_by(stage_id: stage_booked.id).event_type).to eq('rescheduled')
    expect(Crm::BookingRate.count(account, *window)).to eq(0)
  end

  it 'card que NUNCA passou pela coluna chega nela por remarcação: é a primeira vez, conta como agendamento', :aggregate_failures do
    # ex.: a equipe marcou pela Agenda com o card parado em "Envio de Orçamento"
    # e depois a IA remarcou — sem isso o paciente nunca seria contado
    card = card_in(stage_new)
    apply(:rescheduled)
    expect(card.reload.stage_id).to eq(stage_booked.id)
    expect(card.stage_logs.find_by(stage_id: stage_booked.id).event_type).to eq('entered')
    expect(Crm::BookingRate.count(account, *window)).to eq(1)
  end

  it 'card que JÁ passou pela coluna e voltou para trás: a nova passagem por remarcação não conta de novo', :aggregate_failures do
    card = card_in(stage_booked)
    card.update!(stage_id: stage_new.id)
    expect(Crm::BookingRate.count(account, *window)).to eq(1)

    apply(:rescheduled)
    expect(card.reload.stage_id).to eq(stage_booked.id)
    expect(card.stage_logs.where(stage_id: stage_booked.id).order(:id).pluck(:event_type)).to eq(%w[entered rescheduled])
    expect(Crm::BookingRate.count(account, *window)).to eq(1)
  end

  it 'remarcação de quem ainda não tinha card: nasce na coluna e conta (primeira chegada)', :aggregate_failures do
    expect(apply(:rescheduled)[:stage]).to eq('Agendamento de Consulta')
    card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: pipeline.id)
    expect(card.stage_logs.pluck(:event_type)).to eq(['entered'])
    expect(Crm::BookingRate.count(account, *window)).to eq(1)
  end

  it 'agendamento NOVO continua contando', :aggregate_failures do
    other = create(:contact, account: account)
    other_card = Crm::Contact.create!(contact_id: other.id, pipeline_id: pipeline.id, stage_id: stage_new.id)
    described_class.apply(account: account, contact: other, conversation: nil, outcome: :created)
    expect(other_card.reload.stage_logs.find_by(stage_id: stage_booked.id).event_type).to eq('entered')
    expect(Crm::BookingRate.count(account, *window)).to eq(1)
  end
end
