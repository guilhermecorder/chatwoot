require 'rails_helper'

# 🧹 item 345 (14/10): limpeza do agendamento falso da "Ag. Consulta – Google"
RSpec.describe Crm::FalseBookingCleanup do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil CEVICO') }
  let(:budget) { Crm::Stage.create!(pipeline: pipeline, name: 'Envio de Orçamento', position: 1) }
  let(:booking) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 2) }
  let(:confirmed) { Crm::Stage.create!(pipeline: pipeline, name: 'Consulta Confirmada', position: 3) }
  let(:automation) do
    Crm::Automation.create!(stage: budget, name: 'Ag. Consulta – Google', trigger_type: 'label_added', action_type: 'move_card',
                            delay_minutes: 0, active: true, action_config: { 'target_stage_id' => booking.id })
  end
  let(:since) { 1.day.ago }

  # card que a automação empurrou de Envio de Orçamento para Agendamento
  def pushed_card(name)
    contact = create(:contact, account: account, name: name)
    card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: budget)
    card.update!(stage_id: booking.id)
    Crm::AutomationLog.create!(automation: automation, contact_id: contact.id, status: 'fired', payload: {}, fired_at: Time.current)
    card
  end

  def consult!(card, created_at: Time.current, due_at: 3.days.from_now)
    account.tasks.create!(title: "Consulta: #{card.contact.name}", task_type: 'consulta', contact: card.contact, creator: user,
                          due_at: due_at, created_at: created_at)
  end

  it 'sem consulta: entrada sai dos indicadores e o card volta para Envio de Orçamento, quieto', :aggregate_failures do
    card = pushed_card('Marlene')

    rows = described_class.plan(automation, since)
    expect(rows.size).to eq(1)
    expect(rows.first).not_to be_real
    expect(rows.first.back).to be(true)

    result = described_class.apply!(automation, rows)

    expect(result).to eq(marked: 1, moved: 1)
    expect(card.reload.stage_id).to eq(budget.id)
    expect(card.stage_logs.where(stage_id: booking.id).pluck(:event_type)).to eq([described_class::WRONG])
    expect(card.stage_logs.order(:id).last.event_type).to eq(described_class::FIXED)
    expect(Crm::BookingRate.count(account, since, 1.minute.from_now)).to eq(0)
  end

  it 'com consulta marcada de verdade perto dali: fica como está' do
    card = pushed_card('Virginia')
    consult!(card, created_at: 9.minutes.from_now)

    rows = described_class.plan(automation, since)
    described_class.apply!(automation, rows)

    expect(rows.first).to be_real
    expect(card.reload.stage_id).to eq(booking.id)
    expect(card.stage_logs.where(stage_id: booking.id).pluck(:event_type)).to eq(['entered'])
  end

  it 'card que já andou depois (alguém confirmou): só tira a entrada falsa, não mexe no card' do
    card = pushed_card('Fabio')
    travel_to(1.minute.from_now) { card.update!(stage_id: confirmed.id) }

    rows = described_class.plan(automation, since)
    described_class.apply!(automation, rows)

    expect(rows.first.back).to be(false)
    expect(card.reload.stage_id).to eq(confirmed.id)
    expect(card.stage_logs.where(stage_id: booking.id).pluck(:event_type)).to eq([described_class::WRONG])
  end

  it 'paciente que tem consulta futura marcada depois não volta (só a entrada falsa sai)' do
    card = pushed_card('Kelly')
    consult!(card, created_at: 2.hours.from_now)

    rows = described_class.plan(automation, since)

    expect(rows.first).not_to be_real
    expect(rows.first.back).to be(false)
  end

  it 'simulação (plan) não grava nada' do
    card = pushed_card('Cristiano')

    described_class.plan(automation, since)

    expect(card.reload.stage_id).to eq(booking.id)
    expect(card.stage_logs.where(stage_id: booking.id).pluck(:event_type)).to eq(['entered'])
  end

  it 'lista as conversões que saíram junto com a entrada falsa' do
    card = pushed_card('Ana')
    google = Crm::Automation.create!(stage: booking, name: 'Conversão Google (Consulta)', trigger_type: 'card_entered',
                                     action_type: 'google_ads_conversion', delay_minutes: 0, active: true, action_config: {})
    Crm::AutomationLog.create!(automation: google, contact_id: card.contact_id, status: 'fired', payload: {})

    rows = described_class.plan(automation, since)

    expect(described_class.conversions_for(rows).map(&:first)).to eq([google])
  end
end
