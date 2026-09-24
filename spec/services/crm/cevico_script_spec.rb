require 'rails_helper'

RSpec.describe Crm::CevicoScript do
  let(:account) { create(:account) }

  it 'monta o Roteiro padrão com as 6 seções e a tabela de preços oficial' do
    text = described_class.text(account)
    expect(text).to include('ROTEIRO CEVICO')
    described_class::SECTIONS.each { |sec| expect(text).to include("== #{sec['title'].upcase} ==") }
    expect(text).to include('Guilherme, atendente da CEVICO')
    expect(text).not_to include('{{TABELA_DE_PRECOS}}')
    expect(text).to include('PRK R$ 4.900') # tabela padrão do sistema entrou no lugar do marcador
  end

  # 24/09: os 3 médicos como equipe, tabela de exames avulsos, casos especiais e vídeo do médico
  it 'ensina os três médicos, os exames avulsos, os casos especiais e o vídeo do médico (v1 e v2)', :aggregate_failures do
    %w[v1 v2].each do |version|
      text = described_class.text(account, version)
      expect(text).to include('TRÊS oftalmologistas da CEVICO')
      expect(text).to include('avaliam o seu caso em conjunto')
      expect(text).to include('OCT de segmento R$ 700').and include('curva tensional diária R$ 200')
      expect(text).to include('CERATOCONE').and include('LENTE ESCLERAL').and include('Vinicius Almeida')
      expect(text).to include('== VÍDEOS DOS MÉDICOS ==').and include('Dr. Gustavo Bittar · refrativa: https://www.instagram.com/reel/DPUSQsyAjdK/')
      expect(described_class.stage_prompt(account, 'atendente_agendamento', version)).to include('D2. VÍDEO DO MÉDICO')
    end
    expect(described_class::SECTIONS.pluck('key')).to include('doctor_videos')
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

  # 🧪 22/09: Roteiro v2 paralelo (só para o Testar agente)
  describe 'versão v2 (paralela)' do
    it 'tem padrão próprio nas 5 seções, título próprio e os passos dos 2 atendentes como seções extras', :aggregate_failures do
      text = described_class.text(account, 'v2')
      expect(text).to include('ROTEIRO CEVICO 2')
      expect(text).to include('Postura de quem resolve') # persona v2
      expect(text).not_to include('{{TABELA_DE_PRECOS}}')
      sections = described_class.sections(account, 'v2')
      expect(sections.map { |x| x['key'] }).to eq(described_class::SECTIONS.pluck('key') + described_class::STAGE_SECTIONS.pluck('key'))
      expect(sections.last['text']).to include('SEU PAPEL NESTA ETAPA')
      expect(described_class.stage_prompt(account, 'atendente_agendamento', 'v2')).to include('DOIS HORÁRIOS CONCRETOS')
    end

    it 'personalização do v2 vive em script_v2 / prompt_v2 e não encosta no v1', :aggregate_failures do
      CrmSetting.create!(account: account, ai_config: { 'script_v2' => { 'persona' => 'Persona só do v2.' },
                                                        'agents' => { 'atendente_pos' => { 'prompt' => 'Passos v1.',
                                                                                           'prompt_v2' => 'Passos v2.' } } })
      expect(described_class.text(account, 'v2')).to include('Persona só do v2.')
      expect(described_class.text(account)).to include('Guilherme, atendente da CEVICO')
      expect(described_class.text(account)).not_to include('Persona só do v2.')
      expect(described_class.stage_prompt(account, 'atendente_pos', 'v2')).to eq('Passos v2.')
      expect(described_class.stage_prompt(account, 'atendente_pos')).to eq('Passos v1.')
      expect(described_class.sections(account, 'v2').find { |x| x['key'] == 'stage_atendente_pos' }['custom']).to be(true)
    end

    it 'versão desconhecida cai no v1' do
      expect(described_class.normalize_version('v9')).to eq('v1')
      expect(described_class.text(account, nil)).to include('fonte única dos atendentes')
    end
  end
end
