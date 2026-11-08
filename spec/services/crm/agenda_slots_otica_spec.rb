require 'rails_helper'

# 👓 08/11: a Agenda falando a língua da ótica — loja como unidade, faixa do exame (sábado, Fabi), retirada
RSpec.describe Crm::AgendaSlots do
  let(:account) { create(:account) }
  let(:tz) { described_class::TZ }

  before do
    Cevico::Company.save!(account, 'segment' => 'otica', 'units' => [{ 'key' => 'loja', 'label' => 'Loja Jardim Cachoeira' }])
    setting = CrmSetting.find_by!(account: account) # a Identidade da empresa já criou a linha (mantém o ramo e a loja)
    setting.update!(agenda_config: setting.agenda_config.merge(
                         'windows' => [
                           { 'dow' => 1, 'unit' => 'loja', 'doctor' => 'Val', 'start' => '08:00', 'end' => '17:00', 'block' => 30 },
                           { 'dow' => 6, 'unit' => 'loja', 'doctor' => 'Val', 'start' => '08:00', 'end' => '12:00', 'block' => 30 },
                           { 'dow' => 6, 'unit' => 'loja', 'doctor' => 'Fabi', 'start' => '08:00', 'end' => '11:00', 'block' => 10, 'only' => ['exame'] }
                         ]
                       ))
  end

  it 'usa a loja como unidade e os tipos da ótica nos rótulos', :aggregate_failures do
    expect(described_class.otica?(account)).to be(true)
    expect(described_class.unit_labels(account)).to eq('loja' => 'Loja Jardim Cachoeira')
    expect(described_class.unit_label(account, 'loja')).to eq('Loja Jardim Cachoeira')
    expect(described_class.modality_label(account, 'exame')).to eq('exame de vista')
    expect(described_class.modality_label(account, 'avaliacao')).to eq('visita na loja')
    expect(described_class.unit_labels(create(:account))).to eq(described_class::UNIT_LABELS) # clínica: nada muda
  end

  it 'visita comum nunca cai na faixa do exame; o exame só existe no sábado com a Fabi', :aggregate_failures do
    saturday = (tz.now.to_date + 1..tz.now.to_date + 8).find(&:saturday?)
    visita = described_class.free_slots_on(account, saturday)
    exame = described_class.free_slots_on(account, saturday, modality: 'exame')
    expect(visita.map { |s| s[:doctor] }.uniq).to eq(['Val'])
    expect(exame.map { |s| s[:doctor] }.uniq).to eq(['Fabi'])
    expect(exame.map { |s| s[:time] }).to include('08:00', '10:50')
    expect(exame.map { |s| s[:time] }).not_to include('11:00')
    expect(described_class.dedicated_windows?(account, 'exame')).to be(true)
    expect(described_class.dedicated_windows?(account, 'entrega')).to be(false)
    # retirada: sem faixa dedicada, vale qualquer faixa comum da loja
    expect(described_class.free_slots_on(account, saturday, modality: 'entrega').map { |s| s[:doctor] }.uniq).to eq(['Val'])
  end

  it 'o tipo do agendamento sai do procedimento (só na ótica) e as regras falam em loja/visita', :aggregate_failures do
    expect(described_class.booking_modality(account, 'Visita com exame')).to eq('exame')
    expect(described_class.booking_modality(account, 'Retirada do óculos')).to eq('entrega')
    expect(described_class.booking_modality(account, 'Visita: armação e lentes')).to eq('avaliacao')
    expect(described_class.booking_modality(create(:account), 'Exame')).to eq('avaliacao')

    rules = described_class.rules_block(account)
    expect(rules).to include('definidas pela loja').and include('sábado 08:00–11:00 · Loja Jardim Cachoeira · Fabi')
    expect(rules).to include('reservada para exame de vista').and include('NÃO ofereça nem marque visita comum')
    expect(rules).to include('visitas novas por hora')
    expect(described_class.free_slots_text(account, days: 8, modality: 'exame')).to include('Loja Jardim Cachoeira · Fabi')
  end

  describe 'ferramentas e esquema do agente' do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account, name: 'Maria', phone_number: '+5511999990000') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'as ferramentas e o esquema de resposta usam a loja e aceitam o tipo do horário', :aggregate_failures do
      tools = Crm::ResponderTools.new(conversation: conversation, agent_key: 'atendente_pos_op', live: false)
      defs = tools.definitions
      expect(defs.find { |d| d[:name] == 'remarcar_consulta' }.dig(:input_schema, :properties, :unidade, :enum)).to eq(['loja'])
      expect(defs.find { |d| d[:name] == 'horarios_do_dia' }.dig(:input_schema, :properties, :tipo, :enum)).to eq(%w[visita exame entrega])
      expect(defs.pluck(:name)).to include('status_do_pedido')
      expect(defs.pluck(:name)).not_to include('conferir_desconto') # venda é dos atendentes de aquisição

      saturday = (tz.now.to_date + 1..tz.now.to_date + 8).find(&:saturday?)
      out = tools.call('horarios_do_dia', { 'dia' => saturday.iso8601, 'tipo' => 'exame' })
      expect(out[:vagas].first).to include(unidade: 'Loja Jardim Cachoeira', medico: 'Fabi')

      service = Crm::ResponderAgentService.new(conversation: conversation, agent_key: 'atendente_agendamento')
      expect(service.send(:output_schema).dig(:properties, :agendamento, :properties, :unidade, :enum)).to eq(['loja'])
      context = service.send(:context_block)
      expect(context).to include('HORÁRIOS DE EXAME DE VISTA').and include('Fabi')
      expect(context).not_to include('HORÁRIOS PARA RETIRADA')

      pos = Crm::ResponderAgentService.new(conversation: conversation, agent_key: 'atendente_pos_op')
      expect(pos.send(:context_block)).to include('HORÁRIOS PARA RETIRADA DO ÓCULOS').and include('Pedido do cliente (O.S.): nenhum pedido')
    end
  end
end
