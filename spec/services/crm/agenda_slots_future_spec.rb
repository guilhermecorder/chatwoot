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

  # 🚫 item 255: paciente do Oftalmofácil ocupa o horário (nada de agendamento duplo)
  it 'cirurgia e exame do Oftalmofácil ocupam os blocos que sobrepõem, só na unidade deles', :aggregate_failures do
    user = create(:user, account: account)
    free = ->(time, unit = 'paulista') { described_class.slot_available?(account, date: far_wednesday, time: time, unit: unit) }
    expect([free.call('13:00'), free.call('13:15'), free.call('14:00'), free.call('14:30')]).to all(be(true))

    account.tasks.create!(title: 'Cirurgia: Hub', task_type: 'cirurgia', unit: 'paulista', creator: user, source: 'oftalmofacil',
                          external_ref: 'hub-1', due_at: tz.parse("#{far_wednesday} 13:10"))
    account.tasks.create!(title: 'Exame: Hub', task_type: 'consulta', modality: 'exames', unit: 'paulista', creator: user,
                          source: 'oftalmofacil', external_ref: 'hub-2', due_at: tz.parse("#{far_wednesday} 14:20"))
    account.tasks.create!(title: 'Cancelada: Hub', task_type: 'cirurgia', unit: 'paulista', creator: user, source: 'oftalmofacil',
                          external_ref: 'hub-3', due_at: tz.parse("#{far_wednesday} 16:00"), canceled_at: Time.current)

    expect(free.call('13:00')).to be(false) # 13:00–13:15 × cirurgia 13:10–14:10
    expect(free.call('14:00')).to be(false)
    expect(free.call('14:15')).to be(false) # exame 14:20–14:50
    expect(free.call('14:45')).to be(false)
    expect(free.call('15:00')).to be(true)
    expect(free.call('16:00')).to be(true)  # cancelada não ocupa
    expect(free.call('08:30', 'tatuape')).to be(true) # outra unidade
  end
end
