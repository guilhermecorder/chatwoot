require 'rails_helper'

# item 267: fechamento de PARTE do dia — só uma unidade ou só um médico
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  let(:day) { (Date.current + 7.days).then { |d| d + ((3 - d.wday) % 7) } } # próxima quarta

  before do
    CrmSetting.create!(account: account, agenda_config: {
                         'windows' => [
                           { 'dow' => 3, 'start' => '08:00', 'end' => '09:00', 'block' => 30, 'unit' => 'paulista', 'doctor' => 'Dr. A' },
                           { 'dow' => 3, 'start' => '08:00', 'end' => '09:00', 'block' => 30, 'unit' => 'tatuape', 'doctor' => 'Dr. B' }
                         ],
                         'blocked_days' => [{ 'date' => day.to_s, 'unit' => 'tatuape' }]
                       })
  end

  it 'some só a janela da unidade fechada; a outra continua' do
    slots = described_class.free_slots(account, days: 14, per_window: 10).select { |s| s[:date] == day }
    expect(slots.map { |s| s[:unit] }.uniq).to eq(['paulista'])
  end
end
