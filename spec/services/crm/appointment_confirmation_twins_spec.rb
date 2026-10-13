require 'rails_helper'

# 🔁 auditoria 10/2026 (#462/#472): o sim/não do paciente vale para TODAS as
# consultas ativas dele no mesmo dia — pelo WhatsApp, pela assistente de ligação
# ou pelo botão "confirmou" da equipe, tudo passa por Crm::AppointmentConfirmation
RSpec.describe Crm::AppointmentConfirmation do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990092') }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:amanha) { tz.now.beginning_of_day + 1.day }
  let!(:principal) { consulta(amanha + 9.hours) }
  let!(:gemea) { consulta(amanha + 9.hours + 10.minutes, external_ref: 'tok-x', source: 'oftalmofacil', booking_kind: 'registro') }
  let!(:outro_dia) { consulta(amanha + 3.days + 10.hours) }
  let!(:cancelada) { consulta(amanha + 14.hours, canceled_at: Time.current) }

  def consulta(due_at, overrides = {})
    account.tasks.create!({ title: 'Consulta', task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                            due_at: due_at, contact: contact, phone: contact.phone_number }.merge(overrides))
  end

  it 'confirm! (ligação) marca também a outra consulta do dia, sem tocar outro dia nem cancelada', :aggregate_failures do
    described_class.confirm!(account: account, task: principal, contact: contact)
    expect(principal.reload.confirmed_at).to be_present
    expect(gemea.reload.confirmed_at).to be_present
    expect(outro_dia.reload.confirmed_at).to be_nil
    expect(cancelada.reload.confirmed_at).to be_nil
    marks = contact.reload.additional_attributes['cevico_appt_reminders']
    expect(marks[gemea.id.to_s]['confirmed']).to be_present # o reforço não sai mais para a cópia
  end

  it 'decline! marca as duas do dia como "não vai"' do
    described_class.decline!(account: account, task: principal, contact: contact)
    expect(gemea.reload.declined_at).to be_present
    expect(outro_dia.reload.declined_at).to be_nil
  end

  it 'confirm_twins! (botão "confirmou" da equipe) só mexe nas pendentes do dia' do
    gemea.update!(confirmed_at: 1.hour.ago)
    expect { described_class.confirm_twins!(principal, contact) }.not_to(change { gemea.reload.confirmed_at })
  end
end
