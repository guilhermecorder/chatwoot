require 'rails_helper'

# 🗂️ item 307: FAIXA RESERVADA — quarta 13h–14h do Dr. Henrique = só pós-operatório;
# a IA oferece consulta nova a partir das 14h. E "Fechar agenda" do médico vale para a IA.
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  let(:tz) { described_class::TZ }
  let(:wednesday) do
    d = tz.now.to_date + 14
    d += 1 until d.wednesday?
    d
  end
  let(:paulista) do
    ->(modality = 'avaliacao') { described_class.free_slots_on(account, wednesday, unit: 'paulista', modality: modality).pluck(:time) }
  end

  it 'no padrão, a IA só oferece a quarta do Dr. Henrique a partir das 14h', :aggregate_failures do
    expect(paulista.call.first).to eq('14:00')
    expect(paulista.call).not_to include('13:00', '13:15', '13:30', '13:45')
    expect(described_class.slot_available?(account, date: wednesday, time: '13:15', unit: 'paulista')).to be(false)
    expect(described_class.slot_available?(account, date: wednesday, time: '14:15', unit: 'paulista')).to be(true)
  end

  it 'a faixa das 13h continua existindo para o pós-operatório', :aggregate_failures do
    expect(paulista.call('pos_op')).to eq(%w[13:00 13:15 13:30 13:45])
    expect(described_class.slot_available?(account, date: wednesday, time: '13:15', unit: 'paulista', modality: 'pos_op')).to be(true)
  end

  it 'IA remarcando pós-operatório usa SÓ a faixa dedicada; sem faixa dedicada, qualquer faixa que aceite', :aggregate_failures do
    expect(paulista.call('pos_op')).to eq(%w[13:00 13:15 13:30 13:45])
    expect(described_class.slot_available?(account, date: wednesday, time: '14:15', unit: 'paulista', modality: 'pos_op')).to be(false)
    expect(described_class.free_slots_on(account, wednesday, unit: 'tatuape', modality: 'pos_op')).to eq([]) # não há faixa dedicada lá
    expect(paulista.call('retorno').first).to eq('14:00') # retorno não tem faixa dedicada → faixas gerais

    task = Task.new(modality: 'pos_op')
    expect(described_class.slot_modality(task)).to eq('pos_op')
    expect(described_class.slot_modality(Task.new(modality: 'exames'))).to eq('avaliacao')
    expect(described_class.slot_modality(nil)).to eq('avaliacao')
  end

  it 'janela salva sem `only` aceita tudo; `only` desconhecido é ignorado', :aggregate_failures do
    wins = [{ 'dow' => 3, 'unit' => 'paulista', 'doctor' => 'Dr. Henrique Gemelli', 'start' => '13:00', 'end' => '15:00', 'block' => 30,
              'only' => ['inventado'] }]
    CrmSetting.create!(account: account, agenda_config: { 'windows' => wins })
    expect(paulista.call).to eq(%w[13:00 13:30 14:00 14:30])
    expect(described_class.rules_text(account)).to eq('')
  end

  it 'médico com a agenda fechada some das vagas da IA', :aggregate_failures do
    expect(paulista.call).not_to be_empty
    CrmSetting.create!(account: account, agenda_config: { 'closed_doctors' => ['Dr. Henrique Gemelli'] })
    expect(paulista.call).to eq([])
    expect(described_class.free_slots_on(account, wednesday, unit: 'tatuape')).not_to be_empty # Dr. Gustavo segue aberto
  end

  it 'regras para o prompt: faixa reservada + texto da clínica', :aggregate_failures do
    expect(described_class.rules_text(account)).to include('quarta 13:00–14:00 · Av. Paulista · Dr. Henrique Gemelli')
      .and include('retorno de pós-operatório').and include('NÃO ofereça')
    CrmSetting.create!(account: account, agenda_config: { 'ai_rules' => 'Não oferecer encaixe no mesmo dia.' })
    expect(described_class.rules_block(account)).to start_with('REGRAS DA AGENDA').and include('Não oferecer encaixe no mesmo dia.')
  end

  # 🩺 item 311: terça na Av. Paulista — manhã Dr. Henrique, tarde Dra. Roberta
  it 'doctor_at devolve o médico da faixa do horário, não o primeiro do dia', :aggregate_failures do
    tuesday = wednesday - 1
    expect(described_class.doctor_at(account, tuesday, '09:00', 'paulista')).to eq('Dr. Henrique Gemelli')
    expect(described_class.doctor_at(account, tuesday, '14:30', 'paulista')).to eq('Dra. Roberta Negri')
    expect(described_class.doctor_at(account, tuesday, '16:15', 'paulista')).to eq('Dra. Roberta Negri')
    expect(described_class.doctor_at(account, tuesday, '12:30', 'paulista')).to eq('Dr. Henrique Gemelli') # fora de faixa: a 1ª do dia
    expect(described_class.doctor_at(account, wednesday, '13:15', 'paulista', modality: 'pos_op')).to eq('Dr. Henrique Gemelli')
    expect(described_class.doctor_at(account, tuesday, '09:00', 'tatuape')).to be_nil
  end

  it 'sem faixa reservada e sem texto, nada entra no prompt' do
    wins = [{ 'dow' => 3, 'unit' => 'paulista', 'doctor' => 'Dr. Henrique Gemelli', 'start' => '13:00', 'end' => '17:00', 'block' => 15 }]
    CrmSetting.create!(account: account, agenda_config: { 'windows' => wins })
    expect(described_class.rules_block(account)).to eq('')
  end
end
