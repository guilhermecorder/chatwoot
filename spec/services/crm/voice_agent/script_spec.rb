require 'rails_helper'

# 🎙️ rodada 195: o script da voz = Roteiro CEVICO + regras de voz + ferramentas + etapa + trava
RSpec.describe Crm::VoiceAgent::Script do
  let(:account) { create(:account) }
  let(:settings) { Crm::VoiceAgent::Settings.new(account) }

  it 'monta o prompt da ElevenLabs a partir do Roteiro, com a etapa da ligação e tudo falado', :aggregate_failures do
    text = described_class.build(account, settings)
    expect(text).to start_with('ROTEIRO CEVICO')
    expect(text).to include('== REGRAS DE VOZ').and include('== SUAS FERRAMENTAS').and include('== SUA ETAPA ==')
    expect(text).to include('LIGAÇÃO PARA LEAD NÃO RESPONSIVO').and include('{{campanha_objetivo}}').and include('registrar_resultado')
    expect(text).not_to include('Haddad') # 22/09: sem cirurgião nomeado; a autoridade é a equipe + estrutura
    expect(text).to include('Doutor Ricardo')
    expect(text).not_to include('R$')
    expect(text).to include('150 reais').and include('4900 reais').and include('dez vezes sem juros')
    expect(text).to end_with(described_class::GUARDRAIL)
    expect(text).not_to include('{{TABELA_DE_PRECOS}}')
  end

  it 'o bloco da etapa é o do card do agente (agents.voice.prompt) e o Roteiro personalizado entra junto', :aggregate_failures do
    CrmSetting.create!(account: account, ai_config: { 'script' => { 'persona' => 'Você é a Clara, da CEVICO.' },
                                                      'agents' => { 'voice' => { 'prompt' => 'Só confirme a consulta e encerre.' } },
                                                      'voice' => { 'prompt' => 'PROMPT INTEIRO ANTIGO' } })
    text = described_class.build(account, Crm::VoiceAgent::Settings.new(account))
    expect(text).to include('Você é a Clara').and include("== SUA ETAPA ==\nSó confirme a consulta e encerre.")
    expect(text).not_to include('LIGAÇÃO PARA LEAD NÃO RESPONSIVO')
    expect(text).not_to include('PROMPT INTEIRO ANTIGO') # o script inteiro custom da Integração não vale mais
  end

  it 'simulador por texto: variáveis preenchidas, ferramentas mapeadas e trava dos respondedores', :aggregate_failures do
    contact = create(:contact, account: account, name: 'Maria Silva')
    text = described_class.simulator_prompt(account, contact: contact, objective: 'orçamento enviado, sem resposta há dois dias',
                                                     next_appointment: '')
    expect(text).to include('== SIMULADOR POR TEXTO').and include('agendar=true')
    expect(text).to include('Oi, Maria, tudo bem?') # {{primeiro_nome}} preenchido
    expect(text).not_to include('{{')
    expect(text).not_to include('== SUAS FERRAMENTAS') # as da ElevenLabs ficam de fora
    expect(text).to end_with(Crm::AiAgentConfig::RESPONDER_GUARDRAIL)
  end

  it 'Settings: prompt é o bloco da etapa e persist!(prompt:) grava em agents.voice.prompt, não em voice', :aggregate_failures do
    settings.persist!(prompt: 'Passos custom', enabled: true)
    cfg = CrmSetting.find_by(account: account).ai_config
    expect(cfg.dig('agents', 'voice')).to eq('enabled' => true, 'prompt' => 'Passos custom')
    expect(cfg['voice']).not_to have_key('prompt')
    fresh = Crm::VoiceAgent::Settings.new(account)
    expect(fresh.prompt).to eq('Passos custom')
    expect(fresh.to_h[:default_prompt]).to eq(Crm::CevicoScript::STAGE_PROMPTS['voice'])
    expect(fresh.to_h[:full_prompt]).to include('Passos custom').and include('== REGRAS DE VOZ')

    settings.persist!(prompt: '') # vazio = volta ao padrão
    expect(CrmSetting.find_by(account: account).ai_config.dig('agents', 'voice', 'prompt')).to be_nil
  end

  it 'fala números, valores e tempo por extenso' do
    expect(described_class.spoken_money('R$ 4.900 em 10x sem juros ou R$ 150')).to eq('4900 reais em dez vezes sem juros ou 150 reais')
    expect(described_class.spoken_elapsed(1)).to eq('há uma hora')
    expect(described_class.spoken_elapsed(30)).to eq('há trinta horas')
    expect(described_class.spoken_elapsed(48)).to eq('há dois dias')
    expect(described_class.spoken_elapsed(24)).to eq('há vinte e quatro horas')
    expect(described_class.spoken_time('09:20')).to eq('nove e vinte da manhã')
  end
end
