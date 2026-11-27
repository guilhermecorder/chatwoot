require 'rails_helper'

# 🩺 Agendamento Eficiente 1.0 (27/11): avaliação no máximo 4 por hora e UMA A CADA
# 15 MINUTOS; retorno, pós-op e exame ficam livres (podem dividir o horário)
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tz) { described_class::TZ }
  let(:day) do
    d = tz.now.to_date + 14
    d += 1 until d.tuesday?
    d
  end
  let(:block) { 15 }
  let(:extra) { {} }
  let(:config) do
    { 'windows' => [{ 'dow' => 2, 'unit' => 'paulista', 'doctor' => 'Dr. Henrique Gemelli', 'start' => '08:00', 'end' => '10:00',
                      'block' => block }] }.merge(extra)
  end

  before { CrmSetting.create!(account: account, agenda_config: config) }

  def book(time, modality: 'avaliacao')
    account.tasks.create!(title: "Consulta #{time}", task_type: 'consulta', modality: modality, unit: 'paulista', creator: user,
                          due_at: tz.parse("#{day} #{time}"))
  end

  def free_times(**)
    described_class.free_slots_on(account, day, **).map { |s| s[:time] }
  end

  it 'agenda vazia: 08:00, 08:15, 08:30 e 08:45 (uma avaliação a cada 15 minutos)' do
    expect(free_times.grep(/\A08:/)).to eq(%w[08:00 08:15 08:30 08:45])
  end

  it 'cenário seguro do Dr. Henrique: 4 retornos + 4 pós-op na hora não tiram as 4 avaliações', :aggregate_failures do
    %w[08:00 08:15 08:30 08:45].each do |time|
      book(time, modality: 'retorno')
      book(time, modality: 'pos_op')
      book(time, modality: 'exames')
    end
    expect(free_times.grep(/\A08:/)).to eq(%w[08:00 08:15 08:30 08:45])

    %w[08:00 08:15 08:30].each { |time| book(time) }
    expect(free_times.grep(/\A08:/)).to eq(%w[08:45])
  end

  context 'with faixa de 10 em 10 minutos' do
    let(:block) { 10 }

    it 'avaliação às 08:00 tira 08:10 (mesmo quarto de hora), mas 08:20 continua', :aggregate_failures do
      book('08:00')
      expect(free_times.grep(/\A08:/)).to eq(%w[08:20 08:30 08:40 08:50])
      expect(described_class.slot_available?(account, date: day, time: '08:10', unit: 'paulista')).to be(false)
    end

    it 'as 4 por hora continuam cabendo', :aggregate_failures do
      %w[08:00 08:20 08:30].each { |time| book(time) }
      expect(free_times.grep(/\A08:/)).to eq(%w[08:50])
    end

    it 'remarcar retorno não segue o ritmo das avaliações' do
      book('08:00')
      expect(free_times(modality: 'retorno').grep(/\A08:/)).to include('08:10')
    end

    context 'with até 2 avaliações a cada 15 minutos' do
      let(:extra) { { 'quarter_evaluations' => 2 } }

      it 'volta a oferecer 08:10 (mas nunca o mesmo minuto)', :aggregate_failures do
        book('08:00')
        expect(free_times.grep(/\A08:/)).to eq(%w[08:10 08:20 08:30 08:40 08:50])
      end
    end
  end

  it 'configuração saneada: fora de 1–3 volta para 1; modo da tela só block/warn', :aggregate_failures do
    expect(described_class.quarter_cap_from('quarter_evaluations' => 2)).to eq(2)
    expect(described_class.quarter_cap_from('quarter_evaluations' => 9)).to eq(1)
    expect(described_class.quarter_cap_from({})).to eq(1)
    expect(described_class.screen_mode_from('evaluation_screen_mode' => 'warn')).to eq('warn')
    expect(described_class.screen_mode_from('evaluation_screen_mode' => 'x')).to eq('block')
  end

  it 'a regra escrita para os robôs fala dos 15 minutos e deixa retorno/pós-op/exame de fora', :aggregate_failures do
    rule = described_class.hourly_rule(account)
    expect(rule).to include('4 avaliações', 'uma a cada 15 minutos', 'retorno, pós-operatório e exame não entram')
  end

  describe '.evaluation_excess (nota do Secretário)' do
    it 'nada a dizer quando a avaliação está espaçada' do
      book('08:00')
      book('08:15')
      expect(described_class.evaluation_excess(account, tz.parse("#{day} 08:15"), 'paulista')).to eq([])
    end

    it 'avisa duas avaliações no mesmo quarto de hora e a quinta da hora', :aggregate_failures do
      %w[08:00 08:00].each { |time| book(time) }
      issues = described_class.evaluation_excess(account, tz.parse("#{day} 08:00"), 'paulista')
      expect(issues.join).to include('entre 08:00 e 08:14 ficaram 2 avaliações')

      %w[08:15 08:30 08:45].each { |time| book(time) }
      issues = described_class.evaluation_excess(account, tz.parse("#{day} 08:45"), 'paulista')
      expect(issues.join).to include('às 08h ficaram 5 avaliações (o limite é 4 por hora)')
    end

    it 'retorno e pós-op no mesmo horário não geram aviso' do
      book('08:00')
      book('08:00', modality: 'retorno')
      book('08:00', modality: 'pos_op')
      expect(described_class.evaluation_excess(account, tz.parse("#{day} 08:00"), 'paulista')).to eq([])
    end
  end
end
