require 'rails_helper'

# ⏱️ item 367 (23/10): no máximo 4 avaliações por hora em cada unidade, e a lista
# que os robôs oferecem espalha as vagas pelas horas mais vazias do dia
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tz) { described_class::TZ }
  let(:day) do
    d = tz.now.to_date + 14
    d += 1 until d.wednesday?
    d
  end
  let(:config) do
    { 'windows' => [{ 'dow' => 3, 'unit' => 'tatuape', 'doctor' => 'Dr. Gustavo Bittar', 'start' => '08:00', 'end' => '11:00', 'block' => 10 }] }
  end

  before { CrmSetting.create!(account: account, agenda_config: config) }

  def book(time, modality: 'avaliacao', source: nil)
    account.tasks.create!(title: "Consulta #{time}", task_type: 'consulta', modality: modality, unit: 'tatuape', creator: user,
                          source: source, due_at: tz.parse("#{day} #{time}"))
  end

  def free_times(**)
    described_class.free_slots_on(account, day, **).map { |s| s[:time] }
  end

  it 'com 4 avaliações na hora, a hora some para a consulta nova', :aggregate_failures do
    %w[08:00 08:10 08:20 08:30].each { |time| book(time) }

    expect(free_times.grep(/\A08:/)).to eq([])
    expect(free_times).to include('09:00', '10:50')
    expect(described_class.slot_available?(account, date: day, time: '08:40', unit: 'tatuape')).to be(false)
  end

  it 'com 3 avaliações ainda cabe a quarta' do
    %w[08:00 08:10 08:20].each { |time| book(time) }
    expect(free_times.grep(/\A08:/)).to eq(%w[08:30 08:40 08:50])
  end

  it 'exame, retorno, pós-op e teleconsulta não contam; consulta do OftalmoFácil conta', :aggregate_failures do
    book('09:00', modality: 'exames')
    book('09:10', modality: 'retorno')
    book('09:20', modality: 'pos_op')
    book('09:30', modality: 'teleconsulta')
    expect(free_times.grep(/\A09:/)).not_to be_empty

    %w[10:00 10:10].each { |time| book(time) }
    %w[10:20 10:30].each { |time| book(time, source: 'oftalmofacil') }
    expect(free_times.grep(/\A10:/)).to eq([])
  end

  it 'o teto vem da configuração (fora de 1–20 volta para 4)', :aggregate_failures do
    CrmSetting.find_by(account: account).update!(agenda_config: config.merge('hourly_evaluations' => 2))
    %w[08:00 08:10].each { |time| book(time) }
    expect(free_times.grep(/\A08:/)).to eq([])
    expect(described_class.hourly_cap(account)).to eq(2)

    CrmSetting.find_by(account: account).update!(agenda_config: config.merge('hourly_evaluations' => 99))
    expect(described_class.hourly_cap(account)).to eq(4)
  end

  it 'a lista dos robôs espalha: uma vaga por hora, as horas mais vazias primeiro', :aggregate_failures do
    expect(free_times(per_window: 3)).to eq(%w[08:00 09:00 10:00])

    %w[08:00 08:10 08:20].each { |time| book(time) }
    book('09:00')
    # 10h está vazia, 9h tem 1 e 8h tem 3: as duas vagas saem de 10h e 9h
    expect(free_times(per_window: 2)).to eq(%w[09:10 10:00])
  end

  it 'remarcar retorno não respeita o teto das avaliações' do
    %w[08:00 08:10 08:20 08:30].each { |time| book(time) }
    expect(free_times(modality: 'retorno').grep(/\A08:/)).to eq(%w[08:40 08:50])
  end
end
