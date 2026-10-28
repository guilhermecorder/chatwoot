require 'rails_helper'

# 📅 item 375 (28/10): ABERTURA PONTUAL — um dia (ou turno a mais) numa data só,
# na mesma régua das faixas: vagas, horarios_do_dia, médico da faixa e prompt
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  # próxima quinta (a Dra. não atende quinta pela rotina) e a sexta seguinte
  let(:thursday) { (Date.current + 7.days).then { |d| d + ((4 - d.wday) % 7) } }
  let(:friday) { thursday + 1 }
  let(:saturday) { thursday + 2 }
  let(:roberta) { { 'block' => 10, 'unit' => 'tatuape', 'doctor' => 'Dra. Roberta Negri' } }

  before do
    CrmSetting.create!(account: account, agenda_config: {
                         'windows' => [
                           { 'dow' => 5, 'start' => '10:30', 'end' => '13:00', 'block' => 5, 'unit' => 'tatuape', 'doctor' => 'Dra. Roberta Negri' },
                           { 'dow' => 4, 'start' => '08:30', 'end' => '11:00', 'block' => 15, 'unit' => 'paulista', 'doctor' => 'Dr. Gustavo Bittar' }
                         ],
                         'open_days' => [
                           roberta.merge('date' => thursday.to_s, 'start' => '09:00', 'end' => '13:30'),
                           roberta.merge('date' => friday.to_s, 'start' => '13:00', 'end' => '17:30'),
                           { 'date' => saturday.to_s, 'start' => '08:00', 'end' => '10:00', 'block' => 30, 'unit' => 'paulista',
                             'doctor' => 'Dr. Gustavo Bittar' },
                           { 'date' => 'lixo', 'start' => '08:00', 'end' => '10:00', 'unit' => 'paulista', 'doctor' => 'Dr. X' }
                         ]
                       })
  end

  it 'abre um dia em que a médica não atende — só naquela data', :aggregate_failures do
    slots = described_class.free_slots_on(account, thursday, unit: 'tatuape')
    expect(slots.map { |s| s[:doctor] }.uniq).to eq(['Dra. Roberta Negri'])
    expect(slots.map { |s| s[:time] }).to include('09:00', '13:20')
    expect(slots.map { |s| s[:time] }).not_to include('13:30')
    expect(described_class.slot_available?(account, date: thursday, time: '09:10', unit: 'tatuape')).to be(true)
    expect(described_class.doctor_at(account, thursday, '09:10', 'tatuape')).to eq('Dra. Roberta Negri')
    # a quinta seguinte continua sem a Dra. (a rotina da semana não mudou)
    expect(described_class.free_slots_on(account, thursday + 7, unit: 'tatuape')).to be_empty
    # a faixa normal do Dr. Gustavo na quinta segue valendo
    gustavo = described_class.free_slots_on(account, thursday, unit: 'paulista').map { |s| s[:doctor] }.uniq
    expect(gustavo).to eq(['Dr. Gustavo Bittar'])
  end

  it 'soma um turno a um dia em que ela já atende (manhã da rotina + tarde pontual)', :aggregate_failures do
    times = described_class.free_slots_on(account, friday, unit: 'tatuape').map { |s| s[:time] }
    expect(times).to include('10:30', '12:55', '13:00', '17:20')
    expect(times).not_to include('17:30')
    expect(described_class.doctor_at(account, friday, '15:00', 'tatuape')).to eq('Dra. Roberta Negri')
    expect(described_class.free_slots_on(account, friday + 7, unit: 'tatuape').map { |s| s[:time] }).not_to include('13:00')
  end

  it 'um sábado aberto de propósito vale; o sábado seguinte não', :aggregate_failures do
    expect(described_class.free_slots_on(account, saturday).map { |s| s[:time] }).to eq(%w[08:00 08:30 09:00 09:30])
    expect(described_class.free_slots_on(account, saturday + 7)).to be_empty
  end

  it 'cadeados valem em cima da abertura: dia fechado, médico fechado no dia, agenda do médico fechada', :aggregate_failures do
    setting = CrmSetting.find_by(account: account)
    closings = [thursday.to_s, { 'date' => friday.to_s, 'doctor' => 'Dra. Roberta Negri' }]
    setting.update!(agenda_config: setting.agenda_config.merge('blocked_days' => closings))
    expect(described_class.free_slots_on(account, thursday)).to be_empty
    expect(described_class.free_slots_on(account, friday)).to be_empty
    setting.update!(agenda_config: setting.agenda_config.merge('blocked_days' => [], 'closed_doctors' => ['Dra. Roberta Negri']))
    expect(described_class.free_slots_on(account, thursday, unit: 'tatuape')).to be_empty
    expect(described_class.open_days(account).map { |o| o['doctor'] }.uniq).to eq(['Dr. Gustavo Bittar'])
  end

  it 'a abertura entra no prompt como regra (ABERTURA EXTRA) e na lista de vagas', :aggregate_failures do
    day = "quinta #{thursday.strftime('%d/%m')} · Tatuapé · Dra. Roberta Negri"
    expect(described_class.rules_text(account)).to include("ABERTURA EXTRA em #{day}: atende das 09:00 às 13:30")
    expect(described_class.free_slots_text(account, days: 30, per_window: 2)).to include(day)
    expect(described_class.future_open_days(account).size).to eq(3)
  end
end
