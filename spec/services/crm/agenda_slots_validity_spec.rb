require 'rails_helper'

# 🗓️ item 415 (24/11): a Dra. Roberta atrasava e pacientes desistiram. Terça:
# 13h–14h vira hora dos particulares dela; a CEVICO fica 14h–16h30, um paciente
# por horário (sem encaixe). A grade nova entra numa DATA (vigência from/until),
# sem mexer nas terças que já estão marcadas.
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tz) { described_class::TZ }
  let(:change_day) do
    d = tz.now.to_date + 21
    d += 1 until d.tuesday?
    d
  end
  let(:old_tuesday) { change_day - 7 }
  let(:roberta) { 'Dra. Roberta Negri' }
  let(:config) do
    { 'windows' => [
      { 'dow' => 2, 'unit' => 'paulista', 'doctor' => roberta, 'start' => '13:00', 'end' => '16:30', 'block' => 15,
        'until' => (change_day - 1).to_s },
      { 'dow' => 2, 'unit' => 'paulista', 'doctor' => roberta, 'start' => '14:00', 'end' => '16:30', 'block' => 15,
        'from' => change_day.to_s, 'solo' => true }
    ] }
  end

  before { CrmSetting.create!(account: account, agenda_config: config) }

  def book(day, time, modality: 'avaliacao')
    account.tasks.create!(title: "Consulta #{time}", task_type: 'consulta', modality: modality, unit: 'paulista', creator: user,
                          due_at: tz.parse("#{day} #{time}"))
  end

  def free_times(day, **)
    described_class.free_slots_on(account, day, **).map { |s| s[:time] }
  end

  it 'antes da data vale a grade antiga; a partir dela, a nova', :aggregate_failures do
    expect(free_times(old_tuesday).first).to eq('13:00')
    expect(free_times(change_day).first).to eq('14:00')
    expect(free_times(change_day)).not_to include('13:00', '13:45')
    expect(free_times(change_day + 7).first).to eq('14:00')
    expect(described_class.doctor_at(account, change_day, '13:00', 'paulista')).to eq(roberta)
  end

  it 'na faixa sem encaixe, retorno e pós-op também ocupam o horário', :aggregate_failures do
    book(change_day, '14:00', modality: 'retorno')
    book(change_day, '14:15', modality: 'pos_op')
    expect(free_times(change_day)).not_to include('14:00', '14:15')
    expect(free_times(change_day)).to include('14:30')
    expect(described_class.slot_available?(account, date: change_day, time: '14:00', unit: 'paulista')).to be(false)
    # remarcar um retorno também não cai em cima de outro
    expect(free_times(change_day, modality: 'retorno')).not_to include('14:00')
  end

  it 'na faixa com encaixe (a antiga) a avaliação ainda entra em cima do retorno' do
    book(old_tuesday, '14:00', modality: 'retorno')
    expect(free_times(old_tuesday)).to include('14:00')
  end

  it 'faixa reservada com vigência mostra as datas no prompt e some quando acaba', :aggregate_failures do
    wins = config['windows'] + [{ 'dow' => 3, 'unit' => 'paulista', 'doctor' => roberta, 'start' => '13:00', 'end' => '14:00',
                                  'block' => 15, 'only' => ['pos_op'], 'from' => change_day.to_s }]
    CrmSetting.find_by(account: account).update!(agenda_config: { 'windows' => wins })
    expect(described_class.rules_text(account)).to include("(a partir de #{change_day.strftime('%d/%m')})")

    wins.last['until'] = (tz.now.to_date - 1).to_s
    CrmSetting.find_by(account: account).update!(agenda_config: { 'windows' => wins })
    expect(described_class.rules_text(account)).not_to include('retorno de pós-operatório')
  end

  it 'faixa sem vigência continua valendo sempre' do
    CrmSetting.find_by(account: account).update!(agenda_config: { 'windows' => [config['windows'].first.except('until')] })
    expect(free_times(change_day + 14).first).to eq('13:00')
  end
end
