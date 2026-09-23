require 'rails_helper'

# 📆 item 200: agendamento futuro liberado — vagas de um dia específico até 4 meses
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  let(:tz) { described_class::TZ }
  # próxima quarta-feira a pelo menos 5 semanas de distância (fora da lista do prompt)
  let(:far_wednesday) do
    d = tz.now.to_date + 35
    d += 1 until d.wednesday?
    d
  end

  it 'free_slots_on devolve as vagas das janelas daquele dia (quarta: Paulista tarde + Tatuapé manhã)' do
    slots = described_class.free_slots_on(account, far_wednesday, per_window: 2)
    expect(slots.map { |s| s[:unit] }.uniq).to contain_exactly('paulista', 'tatuape')
    expect(slots.find { |s| s[:unit] == 'paulista' }[:time]).to eq('13:00')
    expect(slots.find { |s| s[:unit] == 'tatuape' }[:time]).to eq('08:30')
  end

  it 'filtra por unidade e devolve vazio em fim de semana, dia fechado ou muito longe' do
    expect(described_class.free_slots_on(account, far_wednesday, unit: 'tatuape').map { |s| s[:unit] }.uniq).to eq(['tatuape'])
    expect(described_class.free_slots_on(account, far_wednesday + 3)).to eq([]) # sábado
    expect(described_class.free_slots_on(account, tz.now.to_date + 400)).to eq([])
    CrmSetting.create!(account: account, agenda_config: { 'blocked_days' => [far_wednesday.to_s] })
    expect(described_class.free_slots_on(account, far_wednesday)).to eq([])
  end

  it 'slot_available? enxerga uma vaga bem no futuro e some quando a consulta é marcada' do
    expect(described_class.slot_available?(account, date: far_wednesday, time: '13:15', unit: 'paulista')).to be(true)
    user = create(:user, account: account)
    account.tasks.create!(title: 'Consulta: Ana', task_type: 'consulta', unit: 'paulista', creator: user,
                          due_at: tz.parse("#{far_wednesday} 13:15"))
    expect(described_class.slot_available?(account, date: far_wednesday, time: '13:15', unit: 'paulista')).to be(false)
  end

  it 'free_slots continua igual para os próximos dias' do
    expect(described_class.free_slots(account, days: 14, per_window: 1)).to all(include(:date, :time, :unit, :doctor))
  end
end
