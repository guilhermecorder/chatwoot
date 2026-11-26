require 'rails_helper'

# ⚖️ item 422 (26/11): régua de carga por médico e período (alvo 85, teto 90,
# limite do encaixe 95), espaçamento (encaixe deixa o vizinho livre) e
# equilíbrio entre dias na lista que os robôs oferecem
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tz) { described_class::TZ }
  let(:wed) do
    d = tz.now.to_date + 2
    d += 1 until d.wednesday?
    d
  end
  let(:thu) { wed + 1 }
  # 08:00–10:00 em blocos de 15 = 8 horários por período
  let(:windows) do
    [{ 'dow' => 3, 'unit' => 'tatuape', 'doctor' => 'Dr. Gustavo Bittar', 'start' => '08:00', 'end' => '10:00', 'block' => 15 },
     { 'dow' => 4, 'unit' => 'tatuape', 'doctor' => 'Dr. Gustavo Bittar', 'start' => '08:00', 'end' => '10:00', 'block' => 15 }]
  end
  let(:balance) { { 'enabled' => true, 'balance_days' => 14 } }

  before { configure(balance) }

  def configure(load_balance)
    cfg = { 'windows' => windows, 'hourly_evaluations' => 20 }
    cfg['load_balance'] = load_balance if load_balance
    setting = CrmSetting.find_or_initialize_by(account: account)
    setting.update!(agenda_config: cfg)
  end

  def book(day, time, modality: 'avaliacao')
    account.tasks.create!(title: "Consulta #{day} #{time}", task_type: 'consulta', modality: modality, unit: 'tatuape',
                          creator: user, due_at: tz.parse("#{day} #{time}"))
  end

  def free_times(day, **)
    described_class.free_slots_on(account, day, **).map { |s| s[:time] }
  end

  describe 'espaçamento' do
    it 'o vizinho de um encaixe fica livre', :aggregate_failures do
      book(wed, '09:00', modality: 'retorno')
      book(wed, '09:00')
      times = free_times(wed)
      expect(times).not_to include('08:45', '09:00', '09:15')
      expect(times).to include('08:30', '09:30')
    end

    it 'encaixe em cima de retorno só com os dois vizinhos vazios', :aggregate_failures do
      book(wed, '08:30', modality: 'retorno')
      book(wed, '09:30', modality: 'retorno')
      book(wed, '09:45')
      times = free_times(wed)
      expect(times).to include('08:30') # vizinhos 08:15 e 08:45 vazios
      expect(times).not_to include('09:30') # 09:45 tem gente
    end

    it 'desligado = como antes (encaixe em cima de retorno e vizinho liberados)' do
      configure(nil)
      book(wed, '09:00', modality: 'retorno')
      book(wed, '09:00')
      book(wed, '09:30', modality: 'retorno')
      expect(free_times(wed)).to include('08:45', '09:15', '09:30')
    end

    it 'vale também para remarcar retorno' do
      book(wed, '09:00', modality: 'retorno')
      book(wed, '09:00')
      expect(free_times(wed, modality: 'retorno')).not_to include('08:45', '09:15')
    end
  end

  describe 'carga do período' do
    it 'conta encaixe (2 no mesmo horário = 2) e pode passar de 100' do
      %w[08:00 08:15 08:30 08:45 09:00 09:15 09:30 09:45].each { |t| book(wed, t) }
      book(wed, '09:45', modality: 'retorno')
      expect(described_class.day_loads(account, wed).first[:load]).to eq(113) # 9 pacientes ÷ 8 horários
    end

    it 'exame e teleconsulta não contam; retorno e pós-op contam' do
      book(wed, '08:00', modality: 'exames')
      book(wed, '08:15', modality: 'teleconsulta')
      book(wed, '08:30', modality: 'retorno')
      book(wed, '08:45', modality: 'pos_op')
      expect(described_class.day_loads(account, wed).first[:load]).to eq(25)
    end

    it 'no limite do encaixe (95) nenhum robô marca mais no período', :aggregate_failures do
      %w[08:00 08:15 08:30 08:45 09:00 09:15 09:30].each { |t| book(wed, t) } # 7 de 8 = 88
      expect(free_times(wed)).to eq(['09:45'])
      book(wed, '08:00', modality: 'retorno') # 8 de 8 = 100
      expect(free_times(wed)).to eq([])
      expect(described_class.slot_available?(account, date: wed, time: '09:45', unit: 'tatuape')).to be(false)
      # remarcar retorno/pós-op não segue o limite da consulta nova (só o espaçamento)
      expect(free_times(wed, modality: 'retorno')).to eq(['09:45'])
    end
  end

  describe 'equilíbrio entre dias (lista HORÁRIOS DISPONÍVEIS)' do
    def listed_days
      described_class.free_slots(account, days: 20, per_window: 3).map { |s| s[:date] }.uniq
    end

    it 'enche em níveis: o dia acima de 80 sai enquanto houver dia abaixo', :aggregate_failures do
      %w[08:00 08:15 08:30 08:45 09:00 09:15].each { |t| book(wed, t) } # 75%
      expect(listed_days).to include(wed, thu)

      book(wed, '09:30') # 88%
      expect(listed_days).to include(thu)
      expect(listed_days).not_to include(wed)
    end

    it 'com todos acima de 80 nos dias equilibrados, volta a oferecer até o teto', :aggregate_failures do
      # só quarta e quinta contam para o nível (a semana seguinte, vazia, não empurra o paciente)
      configure(balance.merge('balance_days' => (thu - tz.now.to_date).to_i + 1))
      %w[08:00 08:15 08:30 08:45 09:00 09:15 09:30].each do |t|
        book(wed, t)
        book(thu, t)
      end
      # tudo entre 85 e 90: nível = teto → os dois voltam
      expect(listed_days).to include(wed, thu)
    end

    it 'a semana seguinte vazia entra no nível quando está dentro dos dias equilibrados' do
      %w[08:00 08:15 08:30 08:45 09:00 09:15 09:30].each do |t|
        book(wed, t)
        book(thu, t)
      end
      expect(listed_days).not_to include(wed, thu) # balance_days 14: a próxima semana está a 0%
    end

    it 'dia no teto (90) não aparece na lista, mas segue marcável pela ferramenta até 95', :aggregate_failures do
      configure(balance.merge('ceiling' => 85, 'insist' => 95))
      %w[08:00 08:15 08:30 08:45 09:00 09:15 09:30].each { |t| book(wed, t) } # 88 ≥ 85
      expect(listed_days).not_to include(wed)
      expect(free_times(wed)).to eq(['09:45'])
    end

    it 'desligado = lista como antes' do
      configure(nil)
      %w[08:00 08:15 08:30 08:45 09:00 09:15 09:30].each { |t| book(wed, t) }
      expect(listed_days).to include(wed, thu)
    end
  end

  describe 'configuração e prompt' do
    it 'saneia os números (alvo 50–100, teto ≥ alvo, encaixe ≥ teto)', :aggregate_failures do
      cfg = described_class.balance_from('load_balance' => { 'enabled' => 'true', 'target' => '10', 'ceiling' => '70', 'insist' => '60' })
      expect(cfg).to include('enabled' => true, 'target' => 85, 'ceiling' => 85, 'insist' => 85, 'spacing' => true, 'balance_days' => 7)
      expect(described_class.balance_from({})).to include('enabled' => false, 'target' => 85, 'ceiling' => 90, 'insist' => 95)
    end

    it 'a regra entra no prompt só ligada', :aggregate_failures do
      expect(described_class.rules_text(account)).to include('AGENDA EQUILIBRADA')
      configure(nil)
      expect(described_class.rules_text(account)).not_to include('AGENDA EQUILIBRADA')
    end
  end

  describe 'aviso do Secretário (horário combinado pela equipe)' do
    it 'avisa o acúmulo e sugere horários folgados', :aggregate_failures do
      book(wed, '09:00')
      book(wed, '09:15')
      book(wed, '09:15', modality: 'retorno')
      note = described_class.crowding_note(account, tz.parse("#{wed} 09:15"), 'tatuape')
      expect(note).to include('09:15', 'ficou com 2')
      expect(note).to include('08:00')
    end

    it 'sem acúmulo e abaixo do teto, nada a avisar' do
      book(wed, '09:00')
      expect(described_class.crowding_note(account, tz.parse("#{wed} 09:00"), 'tatuape')).to be_nil
    end
  end
end
