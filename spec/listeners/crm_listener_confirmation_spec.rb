require 'rails_helper'

# varredura 03/10: a recusa vence a confirmação ("ok, não vou conseguir ir")
RSpec.describe CrmListener do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990090') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let!(:task) do
    account.tasks.create!(title: 'Consulta', task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                          due_at: tz.now + 1.day, contact: contact, phone: contact.phone_number)
  end

  before do
    contact.update!(additional_attributes: { 'cevico_appt_reminders' => { task.id.to_s => { 'd1' => Time.current.iso8601 } } })
  end

  def patient_says(text)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: text)
    described_class.instance.send(:handle_appointment_confirmation, message, contact)
  end

  it '"ok, não vou conseguir ir" é recusa, não confirmação', :aggregate_failures do
    patient_says('ok, não vou conseguir ir')
    expect(task.reload.declined_at).to be_present
    expect(task.confirmed_at).to be_nil
  end

  it '"sim, confirmado" continua confirmando' do
    patient_says('sim, confirmado')
    expect(task.reload.confirmed_at).to be_present
  end
end
