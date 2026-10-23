require 'rails_helper'

# 👓 Preparo da VPS da ótica: monta funis, Agenda, atendentes, etiqueta e
# Jornada por NOME, aplica o conteúdo exportado da bancada e pode rodar de
# novo sem duplicar nem desfazer o que o dono mudou pela tela.
RSpec.describe Otica::Preparo do
  let(:account) { create(:account) }
  let(:content) do
    {
      'script' => { 'persona' => 'Persona da loja', 'objections' => 'Objeções da loja', 'segredo' => 'não entra' },
      'prompts' => { 'atendente_agendamento' => 'Etapa de agendamento da loja' },
      'journey' => { 'Óculos pronto para retirar' => 'Texto da loja: óculos pronto' }
    }
  end

  def stage(name)
    Crm::Stage.joins(:pipeline).find_by(crm_pipelines: { account_id: account.id }, name: name)
  end

  it 'monta tudo numa conta vazia, com o conteúdo do arquivo', :aggregate_failures do
    described_class.new(account, content: content).call

    expect(Crm::Pipeline.where(account_id: account.id).order(:position).pluck(:name)).to eq(['Aquisição', 'Pós-venda e relacionamento'])
    expect(Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).count).to eq(18)
    expect(Cevico::Company.for(account).segment).to eq('otica')

    setting = CrmSetting.find_by(account: account)
    expect(setting.agenda_config.dig('booking', 'stage_id')).to eq(stage('Agendamento da visita').id)
    expect(setting.agenda_config.dig('attendance_stages', 'missed_stage_id')).to eq(stage('Desmarcou ou não veio').id)

    agents = setting.ai_config['agents']
    expect(agents.values_at('atendente_agendamento', 'atendente_pos', 'atendente_pos_op').pluck('mode')).to all(eq('shadow'))
    expect(agents['atendente_agendamento']['prompt']).to eq('Etapa de agendamento da loja')
    expect(agents['atendente_pos_op']['stage_ids']).to include(stage('Retirou o óculos').id)
    expect(setting.ai_config['script']).to include('persona' => 'Persona da loja')
    expect(setting.ai_config['script']).not_to have_key('segredo')

    pronto = Crm::JourneyMessage.find_by(account: account, name: 'Óculos pronto para retirar')
    expect(pronto.content['text']).to eq('Texto da loja: óculos pronto')
    expect(pronto.trigger).to include('kind' => 'stage', 'stage_id' => stage('Pronto para retirar').id)
    expect(pronto.approval).to eq('review')
    expect(Crm::JourneyMessage.find_by(account: account, name: 'Parcelas acabaram: próximo óculos').trigger)
      .to include('kind' => 'label', 'label' => 'parcelas_10x', 'offset_days' => 300)
    expect(account.labels.pluck(:title)).to eq(['parcelas_10x'])
  end

  it 'rodar de novo não duplica e não desfaz o que o dono mudou pela tela', :aggregate_failures do
    described_class.new(account, content: content).call
    setting = CrmSetting.find_by(account: account)
    cfg = setting.ai_config.deep_dup
    cfg['agents']['atendente_agendamento']['mode'] = 'live'
    setting.update!(ai_config: cfg)
    pronto = Crm::JourneyMessage.find_by(account: account, name: 'Óculos pronto para retirar')
    pronto.update!(approval: 'auto', content: { 'mode' => 'text', 'text' => 'Texto que o dono editou' })

    expect { described_class.new(account).call }
      .not_to(change { [Crm::Pipeline.count, Crm::Stage.count, Crm::JourneyMessage.count, Label.count] })

    expect(setting.reload.ai_config['agents']['atendente_agendamento']['mode']).to eq('live')
    expect(pronto.reload).to have_attributes(approval: 'auto')
    expect(pronto.content['text']).to eq('Texto que o dono editou')
    expect(setting.ai_config['script']['persona']).to eq('Persona da loja')
  end

  it 'DRY=1 não grava nada' do
    expect { described_class.new(account, dry: true).call }.not_to(change { [Crm::Pipeline.count, Crm::JourneyMessage.count] })
  end

  it 'o export leva o conteúdo e o preparo aceita o que ele gera', :aggregate_failures do
    described_class.new(account, content: content).call
    exported = Otica::ConteudoExport.new(account).call
    expect(exported['script']['persona']).to eq('Persona da loja')
    expect(exported['prompts']['atendente_agendamento']).to eq('Etapa de agendamento da loja')
    expect(exported['journey']['Óculos pronto para retirar']).to eq('Texto da loja: óculos pronto')

    other = create(:account)
    described_class.new(other, content: JSON.parse(exported.to_json)).call
    expect(CrmSetting.find_by(account: other).ai_config['script']['objections']).to eq('Objeções da loja')
  end
end
