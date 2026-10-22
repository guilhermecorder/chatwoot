require 'rails_helper'

# 💰 item 324 (05/10): de onde sai o valor de um agendamento — lançado à mão →
# observação → pré-configurado do tipo (particular por médico, exames,
# avaliação, retorno, pós-op) → valor padrão do lembrete.
RSpec.describe Crm::AppointmentPrice do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, name: 'Ana Recepção') }
  let(:prices) do
    { 'avaliacao' => '150', 'retorno' => 'sem custo', 'pos_op' => 'sem custo',
      'particular' => { 'Dra. Roberta Negri' => 'R$ 450' },
      'exames' => [{ 'name' => 'Pentacam', 'price' => '350' }, { 'name' => 'Topografia', 'price' => '200,00' }, { 'name' => '', 'price' => '9' }] }
  end
  let(:cfg) { described_class::DEFAULTS.merge(described_class.sanitize(prices)) }

  def consulta(attrs = {})
    Task.new({ account: account, creator: user, title: 'Consulta: Paciente', task_type: 'consulta', modality: 'avaliacao' }.merge(attrs))
  end

  it 'arruma o que a tela manda: número vira dinheiro, texto fica texto, exame sem nome sai' do
    expect(cfg).to include('avaliacao' => '150,00', 'retorno' => 'sem custo', 'particular' => { 'Dra. Roberta Negri' => '450,00' })
    expect(cfg['exames']).to eq([{ 'name' => 'Pentacam', 'price' => '350,00' }, { 'name' => 'Topografia', 'price' => '200,00' }])
    expect(described_class.tidy('1250,5')).to eq('1.250,50')
    expect(described_class.tidy('150.00')).to eq('150,00')
  end

  it 'pré-configurado por tipo: avaliação, retorno e pós-operatório', :aggregate_failures do
    expect(described_class.resolve(cfg, consulta)).to include(text: '150,00', source: 'preset')
    expect(described_class.resolve(cfg, consulta(modality: 'retorno'))).to include(text: 'sem custo', source: 'preset')
    expect(described_class.resolve(cfg, consulta(modality: 'pos_op'))).to include(text: 'sem custo')
  end

  it 'consulta PARTICULAR usa o valor do médico; sem valor do médico cai no do tipo', :aggregate_failures do
    roberta = consulta(particular: true, doctor: 'Dra. Roberta Negri')
    expect(described_class.resolve(cfg, roberta)).to include(text: '450,00', source: 'particular')
    expect(described_class.resolve(cfg, consulta(particular: true, doctor: 'Dr. Gustavo Bittar'))).to include(text: '150,00', source: 'preset')
    expect(described_class.resolve(cfg, consulta(doctor: 'Dra. Roberta Negri'))).to include(text: '150,00') # não é particular
  end

  # 🩺 19/10 (Vaneide): "agendou com especialista em retina, só que o valor não subiu"
  it 'avaliação com especialista: o problema escrito puxa o valor do especialista (padrão do Roteiro)', :aggregate_failures do
    expect(described_class.resolve(cfg, consulta(procedure: 'avaliação retina', doctor: 'Dr. Henrique Gemelli')))
      .to include(text: '300,00', source: 'preset', label: 'pré-configurado · avaliação de retina')
    expect(described_class.resolve(cfg, consulta(procedure: 'Avaliação Glaucoma'))).to include(text: '300,00')
    expect(described_class.resolve(cfg, consulta(procedure: 'ceratocone'))).to include(text: '350,00')
    expect(described_class.resolve(cfg, consulta(procedure: 'miopia'))).to include(text: '150,00')
    expect(described_class.resolve(cfg, consulta(modality: 'retorno', procedure: 'retorno glaucoma'))).to include(text: 'sem custo')
    # valor lançado à mão continua vencendo
    expect(described_class.resolve(cfg, consulta(procedure: 'retina', description: 'Valor: 280'))).to include(text: '280,00', source: 'observacao')
  end

  it 'a tela pode trocar os especiais; lista vazia = nenhum' do
    custom = described_class::DEFAULTS.merge(described_class.sanitize(prices.merge('especiais' => [{ 'name' => 'Retina', 'price' => '400' }])))
    expect(custom['especiais']).to eq([{ 'name' => 'Retina', 'price' => '400,00' }])
    expect(described_class.resolve(custom, consulta(procedure: 'avaliação retina'))).to include(text: '400,00')
    expect(described_class.resolve(custom, consulta(procedure: 'glaucoma'))).to include(text: '150,00')
  end

  it 'exames: soma os exames citados no agendamento' do
    exame = consulta(modality: 'exames', procedure: 'Pentacam + topografia')
    expect(described_class.resolve(cfg, exame)).to include(text: '550,00', label: 'pré-configurado · Pentacam + Topografia')
  end

  it 'valor LANÇADO À MÃO vence tudo, e guarda quem lançou; a observação vence o pré-configurado', :aggregate_failures do
    task = consulta(particular: true, doctor: 'Dra. Roberta Negri', description: 'Valor: 300')
    expect(described_class.resolve(cfg, task)).to include(text: '300,00', source: 'observacao')

    task.assign_charges(
      [{ 'label' => 'Consulta', 'amount' => '500' }, { 'label' => 'Exame', 'amount' => 'R$ 120,5' }, { 'label' => 'vazio', 'amount' => '' }], user
    )
    expect(task.charges.pluck('amount', 'by_name')).to eq([['500,00', 'Ana Recepção'], ['120,50', 'Ana Recepção']])
    expect(described_class.resolve(cfg, task)).to include(text: '620,50', source: 'manual', by: 'Ana Recepção')
  end

  it 'linha que não mudou mantém quem lançou; linha alterada ganha o novo nome' do
    task = consulta
    task.assign_charges([{ 'label' => 'Consulta', 'amount' => '500' }], user)
    outra = create(:user, account: account, name: 'Bia')
    task.assign_charges([{ 'label' => 'Consulta', 'amount' => '500' }, { 'label' => 'Exame', 'amount' => '80' }], outra)
    expect(task.charges.pluck('label', 'by_name')).to eq([['Consulta', 'Ana Recepção'], %w[Exame Bia]])
  end

  it 'sem nada configurado: avaliação segue o valor padrão do lembrete; retorno e pós-op saem sem custo', :aggregate_failures do
    blank = described_class.config(account)
    expect(described_class.resolve(blank, consulta, fallback: '180,00')).to include(text: '180,00', source: 'padrao')
    expect(described_class.resolve(blank, consulta)).to include(text: '150,00')
    expect(described_class.resolve(blank, consulta(modality: 'retorno'), fallback: '180,00')).to include(text: 'sem custo')
  end

  # 💰 item 340: confirmação do Alessandro saiu "R$ 150" com a Agenda em R$ 350
  describe 'item 340: tipo de consulta e blocos antigos da IA' do
    let(:legacy) do
      "Paciente prefere manhã\n\nReagendada pela IA:\nValor da consulta: R$ 150\nQuer refrativa\nConversa #12 — agendado pela IA"
    end

    it 'lê o R$ escrito no TIPO de consulta antes do pré-configurado', :aggregate_failures do
      task = consulta(procedure: 'CONSULTA | JÁ PAC | R$350')
      expect(described_class.resolve(cfg, task)).to include(text: '350,00', source: 'procedimento', label: 'escrito no tipo de consulta')
      refrativa = consulta(procedure: 'CONSULTA REFRATIVA | R$ 150 | Dr. X')
      expect(described_class.resolve(cfg, refrativa)).to include(text: '150,00', source: 'procedimento')
    end

    it 'ignora o "Valor da consulta: R$ 150" que a IA gravava (consulta nova e remarcação)', :aggregate_failures do
      task = consulta(description: legacy, procedure: 'CONSULTA | JÁ PAC | R$350')
      expect(described_class.human_notes(legacy)).to eq('Paciente prefere manhã')
      expect(described_class.resolve(cfg, task)).to include(text: '350,00', source: 'procedimento')

      nova = consulta(description: "Valor da consulta: R$ 150\nConversa #9 — agendado pela IA\nValor: 280")
      expect(described_class.resolve(cfg, nova)).to include(text: '280,00', source: 'observacao') # linha da equipe depois do carimbo
      expect(described_class.from_notes("Valor da consulta: R$ 150\nQuer refrativa")).to be_nil # backfill sem carimbo
    end

    it '"Valor: X" da equipe vence o tipo; "R$ X" solto fica depois do pré-configurado', :aggregate_failures do
      expect(described_class.resolve(cfg, consulta(description: 'Valor: 280', procedure: 'CONSULTA | R$350'))).to include(text: '280,00')
      expect(described_class.resolve(cfg, consulta(description: 'trouxe R$ 90'))).to include(text: '150,00', source: 'preset')
      expect(described_class.resolve(described_class.config(account), consulta(modality: 'teleconsulta', description: 'cobrar R$ 90')))
        .to include(text: '90,00', source: 'observacao')
    end

    it 'limpeza: tira SÓ a linha antiga da IA e mantém o resto (rake cevico:limpar_valor_ia)', :aggregate_failures do
      expect(described_class.legacy_ai_value?(legacy)).to be(true)
      expect(described_class.without_legacy_ai_value(legacy))
        .to eq("Paciente prefere manhã\n\nReagendada pela IA:\nQuer refrativa\nConversa #12 — agendado pela IA")
      expect(described_class.legacy_ai_value?("Valor da consulta: R$ 350\nobs da recepção")).to be(false) # escrito pela equipe
      expect(described_class.legacy_ai_value?('Valor citado na conversa pela IA (não vale como valor da consulta): 150')).to be(false)
    end
  end

  it 'cirurgia só tem valor quando alguém lança à mão' do
    cirurgia = Task.new(account: account, creator: user, title: 'Cirurgia: X', task_type: 'cirurgia')
    expect(described_class.resolve(cfg, cirurgia)).to be_nil
    cirurgia.assign_charges([{ 'label' => 'Entrada', 'amount' => '2000' }], user)
    expect(described_class.resolve(cfg, cirurgia)).to include(text: '2.000,00', source: 'manual')
  end
end
