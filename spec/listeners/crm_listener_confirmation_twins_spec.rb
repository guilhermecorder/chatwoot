require 'rails_helper'

# 🔁 auditoria 10/2026 (#462/#472): a mesma consulta registrada duas vezes no
# mesmo dia (recepção + hub) — o "sim"/"não" do paciente vale para as duas;
# antes só a primeira era marcada e a outra seguia recebendo D-1/D-0/reforço.
RSpec.describe CrmListener do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990091') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:amanha) { tz.now.beginning_of_day + 1.day }
  let!(:recepcao) { consulta(amanha + 9.hours) }
  let!(:hub) { consulta(amanha + 9.hours + 10.minutes, external_ref: 'tok-x', source: 'oftalmofacil', booking_kind: 'registro') }
  let!(:outro_dia) { consulta(amanha + 3.days + 10.hours) }

  def consulta(due_at, overrides = {})
    account.tasks.create!({ title: 'Consulta', task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                            due_at: due_at, contact: contact, phone: contact.phone_number }.merge(overrides))
  end

  before do
    marks = [recepcao, hub, outro_dia].to_h { |t| [t.id.to_s, { 'd1' => Time.current.iso8601 }] }
    contact.update!(additional_attributes: { 'cevico_appt_reminders' => marks })
  end

  def patient_says(text)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: text)
    described_class.instance.send(:handle_appointment_confirmation, message, contact)
  end

  it '"sim" confirma TODAS as consultas do dia (uma nota só na conversa) e não toca a de outro dia', :aggregate_failures do
    expect { patient_says('sim') }.to change { conversation.messages.where(private: true).count }.by(1)
    expect(recepcao.reload.confirmed_at).to be_present
    expect(hub.reload.confirmed_at).to be_present
    expect(outro_dia.reload.confirmed_at).to be_nil
    marks = contact.reload.additional_attributes['cevico_appt_reminders']
    expect(marks[recepcao.id.to_s]['confirmed']).to be_present
    expect(marks[hub.id.to_s]['confirmed']).to be_present # o reforço não sai mais para a cópia
    expect(marks[outro_dia.id.to_s]).not_to have_key('confirmed')
  end

  it '"não" marca as duas do dia como não confirmadas' do
    patient_says('não')
    expect(recepcao.reload.declined_at).to be_present
    expect(hub.reload.declined_at).to be_present
    expect(outro_dia.reload.declined_at).to be_nil
  end
end
