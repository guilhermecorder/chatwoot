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
    # item 307: 13h–14h é só pós-operatório — a consulta nova começa às 14h
    expect(slots.find { |s| s[:unit] == 'paulista' }[:time]).to eq('14:00')
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
    expect(described_class.slot_available?(account, date: far_wednesday, time: '14:15', unit: 'paulista')).to be(true)
    user = create(:user, account: account)
    account.tasks.create!(title: 'Consulta: Ana', task_type: 'consulta', unit: 'paulista', creator: user,
                          due_at: tz.parse("#{far_wednesday} 14:15"))
    expect(described_class.slot_available?(account, date: far_wednesday, time: '14:15', unit: 'paulista')).to be(false)
  end

  # 🪑 item 330b (06/10): retorno e pós-op não travam o horário para a IA — cabe UMA avaliação
  # encaixada; a avaliação (ou consulta sem tipo) é que fecha o horário
  it 'horário com retorno ou pós-op continua livre para uma avaliação; com avaliação, fecha', :aggregate_failures do
    user = create(:user, account: account)
    free = ->(time) { described_class.slot_available?(account, date: far_wednesday, time: time, unit: 'paulista') }
    mk = lambda do |time, modality|
      account.tasks.create!(title: "Consulta: #{modality}", task_type: 'consulta', modality: modality, unit: 'paulista', creator: user,
                            due_at: tz.parse("#{far_wednesday} #{time}"))
    end

    mk.call('14:00', 'retorno')
    mk.call('14:15', 'pos_op')
    mk.call('14:30', 'avaliacao')
    mk.call('14:45', 'retorno')
    mk.call('14:45', 'avaliacao') # já encaixou uma: fechou
    expect(free.call('14:00')).to be(true)
    expect(free.call('14:15')).to be(true)
    expect(free.call('14:30')).to be(false)
    expect(free.call('14:45')).to be(false)
  end

  it 'free_slots continua igual para os próximos dias' do
    expect(described_class.free_slots(account, days: 14, per_window: 1)).to all(include(:date, :time, :unit, :doctor))
  end

  # 🚫 item 255: paciente do Oftalmofácil ocupa o horário (nada de agendamento duplo)
  # 🩺 item 297: na janela do médico cada um ocupa SÓ o bloco em que começa
  # 🔪 item 330 (06/10): cirurgia e exame do hub NÃO ocupam a janela do médico (agendas independentes)
  it 'cirurgia e exame do Oftalmofácil não tomam o horário de consulta do médico; consulta do hub ocupa o bloco em que começa', :aggregate_failures do
    user = create(:user, account: account)
    free = ->(time, unit = 'paulista') { described_class.slot_available?(account, date: far_wednesday, time: time, unit: unit) }
    expect([free.call('14:00'), free.call('14:15'), free.call('15:00'), free.call('15:30')]).to all(be(true))

    account.tasks.create!(title: 'Cirurgia: Hub', task_type: 'cirurgia', unit: 'paulista', creator: user, source: 'oftalmofacil',
                          external_ref: 'hub-1', due_at: tz.parse("#{far_wednesday} 14:10"))
    account.tasks.create!(title: 'Exame: Hub', task_type: 'consulta', modality: 'exames', unit: 'paulista', creator: user,
                          source: 'oftalmofacil', external_ref: 'hub-2', due_at: tz.parse("#{far_wednesday} 15:20"))
    account.tasks.create!(title: 'Cancelada: Hub', task_type: 'cirurgia', unit: 'paulista', creator: user, source: 'oftalmofacil',
                          external_ref: 'hub-3', due_at: tz.parse("#{far_wednesday} 16:00"), canceled_at: Time.current)

    account.tasks.create!(title: 'Consulta: Hub', task_type: 'consulta', unit: 'paulista', creator: user, source: 'oftalmofacil',
                          external_ref: 'hub-4', due_at: tz.parse("#{far_wednesday} 15:50"))

    expect(free.call('14:00')).to be(true)  # item 330: cirurgia 14:10 é da sala cirúrgica, não do médico
    expect(free.call('14:15')).to be(true)
    expect(free.call('15:00')).to be(true)
    expect(free.call('15:15')).to be(true)  # item 330: exame 15:20 é da agenda de exames
    expect(free.call('15:30')).to be(true)
    expect(free.call('15:45')).to be(false) # consulta do hub 15:50 começa no bloco 15:45–16:00
    expect(free.call('16:00')).to be(true)  # cancelada não ocupa
    expect(free.call('08:30', 'tatuape')).to be(true) # outra unidade
  end
end
