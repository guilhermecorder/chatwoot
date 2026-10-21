require 'rails_helper'

# 📅 item 217: conversa de CONFIRMAÇÃO nunca vira agendamento novo
RSpec.describe Crm::AppointmentApplier do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:starts_at) { Crm::AgendaSlots::TZ.now.tomorrow.change(hour: 11, min: 0) }
  let(:result) do
    { found: true, name: 'Ana Souza', phone: '+5511999990000', starts_at: starts_at, unit: 'tatuape',
      procedure: '', doctor: '', notes: '', price: '', reschedule: false, cancel: false, gender: nil,
      confirmation: true, model: 'x' }
  end

  before do
    CrmSetting.find_or_create_by!(account: account)
    allow(Crm::AppointmentExtractionService).to receive(:new).and_return(instance_double(Crm::AppointmentExtractionService, call: result))
  end

  it 'consulta ainda não está na Agenda → entra como LANÇADA (registro), fora de Consultas agendadas' do
    outcome = described_class.call(account: account, contact: contact, conversation: conversation)
    expect(outcome).to eq(:registered)
    task = account.tasks.where(task_type: 'consulta').last
    expect(task.booking_kind).to eq('registro')
    expect(account.tasks.bookings.where(task_type: 'consulta')).to be_empty
    expect(conversation.messages.where(private: true).last.content).to include('LANÇADA')
  end

  it 'consulta já está na Agenda → nada é criado' do
    account.tasks.create!(title: 'Consulta: Ana Souza', task_type: 'consulta', creator: admin, contact: contact, due_at: starts_at)
    expect { described_class.call(account: account, contact: contact, conversation: conversation) }
      .not_to(change { account.tasks.count })
  end
end
