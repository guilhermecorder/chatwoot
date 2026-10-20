require 'rails_helper'

# 🔒 20/10: Secretário da Agenda lê "combinado dia X" mas o dia está FECHADO → tarefa + nota, nada gravado
RSpec.describe Crm::AppointmentApplier do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:closed_day) { Crm::AgendaSlots::TZ.now.to_date + 10.days }
  let(:starts_at) { Crm::AgendaSlots::TZ.parse("#{closed_day} 11:00") }
  let(:result) do
    { found: true, name: 'Ana Souza', phone: '+5511999990000', starts_at: starts_at, unit: 'tatuape',
      procedure: '', doctor: '', notes: '', price: '', reschedule: false, cancel: false, gender: nil,
      confirmation: false, model: 'x' }
  end

  before do
    create(:user, account: account, role: :administrator) # quem assina a consulta criada pela IA
    CrmSetting.create!(account: account, agenda_config: { 'blocked_days' => [closed_day.to_s] })
    allow(Crm::AppointmentExtractionService).to receive(:new).and_return(instance_double(Crm::AppointmentExtractionService, call: result))
  end

  it 'não grava a consulta, abre a tarefa "Dia fechado" e deixa a nota na conversa', :aggregate_failures do
    expect(described_class.call(account: account, contact: contact, conversation: conversation)).to eq(:dia_fechado)
    expect(account.tasks.where(task_type: 'consulta')).to be_empty
    task = account.tasks.find_by("title LIKE '⚠️ Dia fechado na Agenda%'")
    expect(task).to be_present
    expect(task.description).to include('FECHADO')
    note = conversation.messages.where(private: true).last
    expect(note.content).to include('FECHADO na Agenda')
  end
end
