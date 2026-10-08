require 'rails_helper'

# 🎙️ rodada 195: o script da voz = Roteiro CEVICO + regras de voz + ferramentas + etapa + trava
# 🎙️ item 333: dois roteiros (atender × ligar), persona configurável, valor da avaliação da Agenda e pronúncia
RSpec.describe Crm::VoiceAgent::Script do
  let(:account) { create(:account) }
  let(:settings) { Crm::VoiceAgent::Settings.new(account) }

  it 'monta o prompt da ElevenLabs (ao ATENDER) a partir do Roteiro, com tudo falado e as marcas trocadas', :aggregate_failures do
    text = described_class.build(account, settings)
    expect(text).to start_with('ROTEIRO CEVICO')
    expect(text).to include('== REGRAS DE VOZ').and include('== SUAS FERRAMENTAS').and include('== SUA ETAPA ==')
    expect(text).to include('LIGAÇÃO RECEBIDA').and include('{{campanha_objetivo}}').and include('registrar_resultado')
    expect(text).to include('confirmar_presenca').and include('chamar_equipe').and include('para_outra_pessoa')
    expect(text).not_to include('LIGAÇÃO PARA LEAD NÃO RESPONSIVO')
    expect(text).not_to include('Haddad') # 22/09: sem cirurgião nomeado; a autoridade é a equipe + estrutura
    expect(text).to include('Doutor Ricardo')
    expect(text).not_to include('R$')
    expect(text).to include('150 reais').and include('4900 reais').and include('dez vezes sem juros')
    expect(text).to include('A consulta de avaliação é cento e cinquenta reais')
    expect(text).to include('você é a assistente virtual da CEVICO')
    expect(text).not_to include('{{EU_SOU}}')
    expect(text).not_to include('{{UM_ASSISTENTE}}')
    expect(text).not_to include('{{VALOR_AVALIACAO}}')
    expect(text).to end_with(described_class::GUARDRAIL.gsub('{{UM_ASSISTENTE}}', 'uma assistente virtual'))
    expect(text).not_to include('{{TABELA_DE_PRECOS}}')
  end

  it 'ao LIGAR usa a etapa de lead parado', :aggregate_failures do
    text = described_class.build(account, settings, direction: :outbound)
    expect(text).to include('LIGAÇÃO PARA LEAD NÃO RESPONSIVO').and include('O próximo passo é a consulta de avaliação: cento e cinquenta reais')
    expect(text).not_to include('LIGAÇÃO RECEBIDA')
  end

  it 'cada etapa é a do seu card (agents.voice = ligar; agents.voice_inbound = atender) e o Roteiro personalizado entra junto', :aggregate_failures do
    CrmSetting.create!(account: account, ai_config: { 'script' => { 'persona' => 'Você é a Clara, da CEVICO.' },
                                                      'agents' => { 'voice' => { 'prompt' => 'Só confirme a consulta e encerre.' },
                                                                    'voice_inbound' => { 'prompt' => 'Atenda e marque.' } },
                                                      'voice' => { 'prompt' => 'PROMPT INTEIRO ANTIGO' } })
    fresh = Crm::VoiceAgent::Settings.new(account)
    outbound = described_class.build(account, fresh, direction: :outbound)
    inbound = described_class.build(account, fresh)
    expect(outbound).to include('Você é a Clara').and include("== SUA ETAPA ==\nSó confirme a consulta e encerre.")
    expect(inbound).to include("== SUA ETAPA ==\nAtenda e marque.")
    expect(outbound + inbound).not_to include('PROMPT INTEIRO ANTIGO') # o script inteiro custom da Integração não vale mais
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

  it 'Settings: prompt (ligar) vai para agents.voice e inbound_prompt (atender) para agents.voice_inbound', :aggregate_failures do
    settings.persist!(prompt: 'Passos custom', inbound_prompt: 'Atender assim', enabled: true)
    cfg = CrmSetting.find_by(account: account).ai_config
    expect(cfg.dig('agents', 'voice')).to eq('enabled' => true, 'prompt' => 'Passos custom')
    expect(cfg.dig('agents', 'voice_inbound', 'prompt')).to eq('Atender assim')
    expect(cfg['voice']).not_to have_key('prompt')
    expect(cfg['voice']).not_to have_key('inbound_prompt')
    fresh = Crm::VoiceAgent::Settings.new(account)
    expect(fresh.prompt).to eq('Passos custom')
    expect(fresh.inbound_prompt).to eq('Atender assim')
    expect(fresh.to_h[:default_prompt]).to eq(Crm::CevicoScript::STAGE_PROMPTS['voice'])
    expect(fresh.to_h[:full_prompt]).to include('Atender assim').and include('== REGRAS DE VOZ')

    settings.persist!(prompt: '', inbound_prompt: '') # vazio = volta ao padrão
    cfg = CrmSetting.find_by(account: account).ai_config
    expect(cfg.dig('agents', 'voice', 'prompt')).to be_nil
    expect(cfg.dig('agents', 'voice_inbound', 'prompt')).to be_nil
  end

  it 'persona: nome e gênero mudam a apresentação, a trava e as frases padrão', :aggregate_failures do
    settings.persist!(persona_name: 'Guilherme', persona_gender: 'm')
    fresh = Crm::VoiceAgent::Settings.new(account)
    text = described_class.build(account, fresh)
    expect(text).to include('você é o Guilherme, assistente virtual da CEVICO').and include('Você é um assistente virtual e diz isso')
    expect(fresh.first_message).to eq('Olá! Aqui é o Guilherme, assistente virtual da CEVICO. Posso te ajudar a marcar, ' \
                                      'confirmar ou remarcar a sua consulta. Como posso te ajudar?')
    expect(fresh.outbound_first_message).to start_with('Olá! Aqui é o Guilherme, assistente virtual da CEVICO. A gente conversou')
    expect(fresh.partner_message).to include('o Guilherme').and include('pelo WhatsApp')
    expect(described_class.build(account, fresh, direction: :outbound)).to include('Aqui é o Guilherme, assistente virtual da CEVICO. A gente')
  end

  it 'valor da avaliação vem da Agenda (item 324) e vence o do Roteiro na fala' do
    CrmSetting.create!(account: account, agenda_config: { 'appointment_prices' => { 'avaliacao' => '200,00' } })
    text = described_class.build(account, Crm::VoiceAgent::Settings.new(account))
    expect(text).to include('Valor da consulta de AVALIAÇÃO: duzentos reais').and include('A consulta de avaliação é duzentos reais')
  end

  it 'pronúncia: vira bloco no prompt e vale no texto falado das ferramentas', :aggregate_failures do
    settings.persist!(pronunciations: [{ 'from' => 'Gemelli', 'to' => 'Jeméli' }, { 'from' => '', 'to' => 'x' }])
    fresh = Crm::VoiceAgent::Settings.new(account)
    expect(fresh.pronunciations).to eq([{ 'from' => 'Gemelli', 'to' => 'Jeméli' }])
    expect(described_class.build(account, fresh)).to include('== PRONÚNCIA ==').and include('- Gemelli → escreva "Jeméli"')
    expect(described_class.apply_pronunciation('com Doutor Henrique Gemelli, na unidade', fresh)).to eq('com Doutor Henrique Jeméli, na unidade')
  end

  it 'fala números, valores e tempo por extenso', :aggregate_failures do
    expect(described_class.spoken_money('R$ 4.900 em 10x sem juros ou R$ 150')).to eq('4900 reais em dez vezes sem juros ou 150 reais')
    expect(described_class.spoken_price('150,00')).to eq('cento e cinquenta reais')
    expect(described_class.spoken_price('100')).to eq('cem reais')
    expect(described_class.spoken_price('4.900,00')).to eq('quatro mil e novecentos reais')
    expect(described_class.spoken_price('1.250,50')).to eq('mil duzentos e cinquenta reais e cinquenta centavos')
    expect(described_class.spoken_price('350')).to eq('trezentos e cinquenta reais')
    expect(described_class.spoken_price('sem custo')).to eq('sem custo')
    expect(described_class.spoken_elapsed(1)).to eq('há uma hora')
    expect(described_class.spoken_elapsed(30)).to eq('há trinta horas')
    expect(described_class.spoken_elapsed(48)).to eq('há dois dias')
    expect(described_class.spoken_elapsed(24)).to eq('há vinte e quatro horas')
    expect(described_class.spoken_time('09:20')).to eq('nove e vinte da manhã')
  end
end
