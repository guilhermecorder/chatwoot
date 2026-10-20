require 'rails_helper'

# 🔒 20/10: dia fechado na Agenda (cadeado) — a régua única que trava os robôs
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  let(:day) { (Date.current + 7.days).then { |d| d + ((3 - d.wday) % 7) } } # próxima quarta

  before do
    CrmSetting.create!(account: account, agenda_config: {
                         'windows' => [
                           { 'dow' => 3, 'start' => '08:00', 'end' => '09:00', 'block' => 30, 'unit' => 'paulista', 'doctor' => 'Dr. A' },
                           { 'dow' => 3, 'start' => '08:00', 'end' => '09:00', 'block' => 30, 'unit' => 'tatuape', 'doctor' => 'Dr. B' }
                         ],
                         'closed_doctors' => ['Dr. C'],
                         'blocked_days' => [day.to_s, { 'date' => (day + 7).to_s, 'unit' => 'tatuape' },
                                            { 'date' => (day + 14).to_s, 'doctor' => 'Dr. A' }]
                       })
  end

  it 'dia inteiro fechado: nenhuma vaga e closed_on? para qualquer unidade/médico', :aggregate_failures do
    expect(described_class.free_slots_on(account, day)).to be_empty
    expect(described_class.closed_on?(account, day)).to be(true)
    expect(described_class.closed_on?(account, day, unit: 'paulista', doctor: 'Dr. A')).to be(true)
    expect(described_class.slot_available?(account, date: day, time: '08:00', unit: 'paulista')).to be(false)
  end

  it 'só a unidade fechada trava; a outra e a unidade desconhecida passam', :aggregate_failures do
    expect(described_class.closed_on?(account, day + 7, unit: 'tatuape')).to be(true)
    expect(described_class.closed_on?(account, day + 7, unit: 'paulista')).to be(false)
    expect(described_class.closed_on?(account, day + 7)).to be(false)
  end

  it 'só o médico fechado naquele dia (ou com a agenda fechada) trava', :aggregate_failures do
    expect(described_class.closed_on?(account, day + 14, unit: 'paulista', doctor: 'Dr. A')).to be(true)
    expect(described_class.closed_on?(account, day + 14, unit: 'paulista', doctor: 'Dr. B')).to be(false)
    expect(described_class.closed_on?(account, day + 21, doctor: 'Dr. C')).to be(true)
    expect(described_class.closed_on?(account, day + 21, unit: 'paulista', doctor: 'Dr. A')).to be(false)
  end
end
