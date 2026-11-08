require 'rails_helper'

# ☀️ 08/11: TIPOS DA AGENDA por empresa (a LIFE: Visita técnica + Fechamento) e a
# unidade da Identidade da empresa nos textos da agenda para a IA. A clínica
# (sem nada configurado) segue com os 6 tipos e os textos de sempre.
RSpec.describe Cevico::Company do
  let(:account) { create(:account) }
  let(:life_types) do
    [{ 'key' => 'avaliacao', 'label' => 'Visita técnica', 'noun' => 'visita técnica', 'plural' => 'visitas técnicas',
       'hint' => 'ver telhado e estrutura no imóvel do cliente', 'icon' => 'i-lucide-house' },
     { 'key' => 'retorno', 'label' => 'Fechamento', 'noun' => 'fechamento', 'plural' => 'fechamentos',
       'hint' => 'reunião para fechar o negócio', 'icon' => 'i-lucide-handshake' }]
  end

  describe '.sanitize_agenda_types' do
    it 'aceita só as chaves dos tipos de sempre, sem repetir, no máximo 6', :aggregate_failures do
      list = [{ key: 'avaliacao', label: 'Visita' }, { key: 'inventado', label: 'X' }, { key: 'avaliacao', label: 'De novo' },
              { key: 'retorno', label: 'Fechamento' }, 'lixo', nil] +
             %w[pos_op exames teleconsulta cirurgia].map { |k| { key: k, label: k } } + [{ key: 'retorno', label: 'Y' }]
      out = described_class.sanitize_agenda_types(list)
      expect(out.pluck('key')).to eq(%w[avaliacao retorno pos_op exames teleconsulta cirurgia])
      expect(out.first['label']).to eq('Visita')
      expect(described_class.sanitize_agenda_types(nil)).to eq([])
    end

    it 'corta os textos, recusa ícone e artigo estranhos', :aggregate_failures do
      out = described_class.sanitize_agenda_types([{ 'key' => 'avaliacao', 'label' => "  #{'a' * 60}  ", 'hint' => 'h' * 300,
                                                     'icon' => 'fa fa-<script>', 'article' => 'x', 'extra' => 'y' }]).first
      expect(out['label'].size).to eq(40)
      expect(out['hint'].size).to eq(120)
      expect(out).not_to include('icon', 'article', 'extra')
      ok = described_class.sanitize_agenda_types([{ 'key' => 'retorno', 'icon' => 'i-lucide-handshake', 'article' => 'o' }]).first
      expect(ok).to eq('key' => 'retorno', 'icon' => 'i-lucide-handshake', 'article' => 'o')
    end
  end

  it 'save! grava os tipos limpos, to_h devolve para a tela e o resto da Identidade fica', :aggregate_failures do
    described_class.save!(account, { 'name' => 'Life Energia Solar', 'segment' => 'outro' })
    company = described_class.save!(account, { 'agenda_types' => life_types + [{ 'key' => 'nao_existe', 'label' => 'X' }] })
    expect(company.name).to eq('Life Energia Solar')
    expect(company.to_h[:agenda_types].pluck('key')).to eq(%w[avaliacao retorno])
    expect(company.to_h[:agenda_types].first).to include('label' => 'Visita técnica', 'icon' => 'i-lucide-house')
    expect(company.agenda_type_noun('avaliacao')).to eq('visita técnica')
    expect(company.agenda_type_plural('retorno')).to eq('fechamentos')
    expect(company.agenda_type_noun('pos_op')).to be_nil
    expect(described_class.save!(account, { 'agenda_types' => [] }).agenda_types).to eq([])
  end

  it 'clínica sem nada configurado: nenhum tipo próprio' do
    expect(described_class.for(account).to_h[:agenda_types]).to eq([])
  end

  describe 'textos da agenda para a IA (Crm::AgendaSlots)' do
    let(:slots) { Crm::AgendaSlots }

    it 'clínica: os textos de sempre', :aggregate_failures do
      expect(slots.rules_block(account)).to include('definidas pela clínica — valem acima de qualquer horário que o paciente peça')
        .and include('avaliações (consultas novas)')
      expect(slots.rules_text(account)).to include('· Av. Paulista · Dr. Henrique Gemelli').and include('remarcar retorno de pós-operatório')
      expect(slots.own_agenda?(account)).to be(false)
    end

    it 'LIFE: unidade da Identidade, Fernando, visitas técnicas e cliente', :aggregate_failures do
      described_class.save!(account, { 'segment' => 'outro', 'agenda_types' => life_types,
                                       'units' => [{ 'key' => 'piracicaba', 'label' => 'Piracicaba · Av. Dr. Morato, 233' }] })
      wins = [{ 'dow' => 2, 'unit' => 'piracicaba', 'doctor' => 'Fernando', 'start' => '08:00', 'end' => '09:00', 'block' => 60,
                'only' => ['retorno'] },
              { 'dow' => 2, 'unit' => 'piracicaba', 'doctor' => 'Fernando', 'start' => '09:00', 'end' => '17:00', 'block' => 60 }]
      Cevico::SettingMerge.merge!(account, :agenda_config) { |cfg| cfg.merge('windows' => wins) }

      expect(slots.own_agenda?(account)).to be(true)
      expect(slots.unit_label(account, 'piracicaba')).to eq('Piracicaba · Av. Dr. Morato, 233')
      rules = slots.rules_block(account)
      expect(rules).to include('definidas pela empresa — valem acima de qualquer horário que o cliente peça')
      expect(rules).to include('terça 08:00–09:00 · Piracicaba · Av. Dr. Morato, 233 · Fernando: faixa reservada para fechamento')
      expect(rules).to include('NÃO ofereça nem marque visita técnica nesta faixa').and include('visitas técnicas por hora')
      expect(slots.free_slots_text(account, days: 14)).to include('· Piracicaba · Av. Dr. Morato, 233 · Fernando:')
    end

    it 'LIFE sem faixa no sábado: o sábado segue fechado' do
      described_class.save!(account, { 'segment' => 'outro', 'units' => [{ 'key' => 'piracicaba', 'label' => 'Piracicaba' }] })
      wins = (1..5).map { |d| { 'dow' => d, 'unit' => 'piracicaba', 'doctor' => 'Fernando', 'start' => '08:00', 'end' => '17:00', 'block' => 60 } }
      Cevico::SettingMerge.merge!(account, :agenda_config) { |cfg| cfg.merge('windows' => wins) }
      saturday = Crm::AgendaSlots::TZ.now.to_date + 7
      saturday += 1 until saturday.saturday?
      expect(slots.free_slots_on(account, saturday)).to eq([])
    end
  end
end
