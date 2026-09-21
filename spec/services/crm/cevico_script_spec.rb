require 'rails_helper'

RSpec.describe Crm::CevicoScript do
  let(:account) { create(:account) }

  it 'monta o Roteiro padrão com as 5 seções e a tabela de preços oficial' do
    text = described_class.text(account)
    expect(text).to include('ROTEIRO CEVICO')
    described_class::SECTIONS.each { |sec| expect(text).to include("== #{sec['title'].upcase} ==") }
    expect(text).to include('Guilherme, atendente da CEVICO')
    expect(text).not_to include('{{TABELA_DE_PRECOS}}')
    expect(text).to include('PRK R$ 4.900') # tabela padrão do sistema entrou no lugar do marcador
  end

  it 'seção personalizada vence o padrão; seção em branco volta ao padrão' do
    CrmSetting.create!(account: account, ai_config: { 'script' => { 'persona' => 'Você é a Vanessa, da CEVICO.', 'handoff' => '   ' } })
    sections = described_class.sections(account).index_by { |s| s['key'] }

    expect(sections['persona']['text']).to eq('Você é a Vanessa, da CEVICO.')
    expect(sections['persona']['custom']).to be(true)
    expect(sections['handoff']['text']).to eq(described_class::DEFAULT['handoff'])
    expect(sections['handoff']['custom']).to be(false)
    expect(described_class.text(account)).to include('Você é a Vanessa').and include(described_class::DEFAULT['form_rules'].lines.first.strip)
  end

  it 'bloco da etapa: o prompt do card do agente substitui o padrão' do
    expect(described_class.stage_prompt(account, 'atendente_agendamento')).to include('SEU PAPEL NESTA ETAPA')

    CrmSetting.create!(account: account, ai_config: { 'agents' => { 'atendente_agendamento' => { 'prompt' => 'Só agende, sem sondagem.' } } })
    expect(described_class.stage_prompt(account, 'atendente_agendamento')).to eq('Só agende, sem sondagem.')
  end

  it 'as etapas dos dois atendentes ensinam as ferramentas (192)', :aggregate_failures do
    %w[atendente_agendamento atendente_pos].each do |key|
      prompt = described_class.stage_prompt(account, key)
      expect(prompt).to include('FERRAMENTAS')
      Crm::ResponderTools::NAMES.each { |name| expect(prompt).to include(name) }
      expect(prompt).to include('ok=true').and include('simulado=true')
    end
  end
end
