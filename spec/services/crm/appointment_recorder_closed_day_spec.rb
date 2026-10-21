require 'rails_helper'

# 🔒 20/10 ("quando alguém fechar o dia na agenda, o agente não agende"): a trava
# mora no gravador único — vale para Secretário, Instagram, WhatsApp e ligação
RSpec.describe Crm::AppointmentRecorder do
  let(:account) { create(:account) }
  let(:tz) { Crm::AgendaSlots::TZ }
  let(:closed_day) { tz.now.to_date + 10.days }
  let(:closed_at) { tz.parse("#{closed_day} 10:00") }
  let(:open_at) { tz.parse("#{closed_day + 1} 10:00") }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }

  before do
    create(:user, account: account, role: :administrator) # quem assina a consulta criada pela IA
    CrmSetting.create!(account: account, agenda_config: {
                         'blocked_days' => [closed_day.to_s, { 'date' => (closed_day + 2).to_s, 'unit' => 'tatuape' }]
                       })
  end

  def record(starts_at, unit: 'paulista', booking_kind: nil)
    described_class.record(account: account, contact: contact, booking_kind: booking_kind,
                           result: { found: true, starts_at: starts_at, name: 'Maria Silva', phone: '+5511999990000', unit: unit })
  end

  it 'dia inteiro fechado: não grava nada e devolve :dia_fechado (fica no registro do Secretário)', :aggregate_failures do
    expect(record(closed_at)).to eq(:dia_fechado)
    expect(account.tasks.where(task_type: 'consulta')).to be_empty
    expect(CrmSetting.find_by(account: account).agenda_config.dig('scheduler_log', 0, 'outcome')).to eq('dia_fechado')
  end

  it 'dia aberto grava normalmente' do
    expect(record(open_at)).to eq(:created)
  end

  it 'unidade fechada trava só ela', :aggregate_failures do
    at = tz.parse("#{closed_day + 2} 10:00")
    expect(record(at, unit: 'tatuape')).to eq(:dia_fechado)
    expect(record(at, unit: 'paulista')).to eq(:created)
  end

  it 'remarcar PARA um dia fechado não move a consulta existente', :aggregate_failures do
    expect(record(open_at)).to eq(:created)
    task = account.tasks.find_by(title: 'Consulta: Maria Silva')
    expect(record(closed_at)).to eq(:dia_fechado)
    expect(task.reload.due_at).to be_within(1.second).of(open_at)
  end

  it 'registro de consulta já marcada fora do sistema (item 217) passa' do
    expect(record(closed_at, booking_kind: 'registro')).to eq(:created)
  end

  it 'data passada (histórico) não é travada' do
    past = tz.now - 30.days
    CrmSetting.find_by(account: account).update!(agenda_config: { 'blocked_days' => [past.to_date.to_s] })
    expect(record(past)).to eq(:created)
  end
end
