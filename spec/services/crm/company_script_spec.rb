require 'rails_helper'

# 🏢 rodada 334: o Roteiro e os prompts seguem a EMPRESA da conta.
# Clínica (padrão, sem configuração) = texto idêntico ao de sempre;
# ótica = roteiro genérico com o nome, as lojas e o vocabulário dela.
RSpec.describe Crm::CompanyScript do
  let(:clinic) { create(:account) }
  let(:otica) { create(:account, name: 'Sua Ótica') }

  before do
    Cevico::Company.save!(otica, 'name' => 'Sua Ótica', 'segment' => 'otica', 'offers' => 'óculos de grau, lentes de contato e óculos de sol',
                                 'tone' => 'leve e próximo', 'assistant' => { 'name' => 'Ana', 'gender' => 'f' },
                                 'units' => [{ 'label' => 'Loja Moema', 'address' => 'Al. dos Anapurus, 100', 'phone' => '11999990000' },
                                             { 'label' => 'Loja Tatuapé' }])
  end

  describe 'clínica: nada muda' do
    it 'o Roteiro inteiro é exatamente o de sempre (seções padrão + tabela + regra por olho)', :aggregate_failures do
      body = Crm::CevicoScript::SECTIONS.map { |s| "== #{s['title'].upcase} ==\n#{Crm::CevicoScript::DEFAULT[s['key']]}" }.join("\n\n")
      body = body.gsub('{{TABELA_DE_PRECOS}}', Cevico::PriceList.prompt_block(clinic))
      body = "#{body}\n\n== REGRA FIXA DE VALORES ==\n#{Cevico::PriceList::PER_EYE_RULE}" unless body.include?(Cevico::PriceList::PER_EYE_RULE)
      expected = "ROTEIRO CEVICO 1 · Fiel ao N8N (fonte única dos atendentes)\n\n#{body}"

      expect(Crm::CevicoScript.text(clinic)).to eq(expected)
      expect(Crm::CevicoScript.text(clinic, 'v2')).to start_with('ROTEIRO CEVICO 2')
    end

    it 'seções e etapas padrão são as constantes da clínica, com ou sem conta', :aggregate_failures do
      Crm::CevicoScript::SECTIONS.pluck('key').each do |key|
        expect(Crm::CevicoScript.default_text(key, 'v1', account: clinic)).to eq(Crm::CevicoScript::DEFAULT[key])
        expect(Crm::CevicoScript.default_text(key)).to eq(Crm::CevicoScript::DEFAULT[key])
      end
      %w[atendente_agendamento atendente_pos atendente_pos_op voice voice_inbound].each do |agent|
        expect(Crm::CevicoScript.stage_prompt(clinic, agent)).to eq(Crm::CevicoScript::STAGE_PROMPTS[agent])
      end
      expect(Crm::CevicoScript.sections(clinic).map { |s| s['custom'] }).to all(be(false))
    end

    it 'os prompts dos agentes continuam as constantes e o schema é o mesmo objeto', :aggregate_failures do
      service = Crm::ConversationInsightService.allocate
      service.instance_variable_set(:@account, clinic)
      expect(service.send(:default_system_prompt)).to equal(Crm::ConversationInsightService::SYSTEM_PROMPT)
      expect(service.send(:company_schema, Crm::ConversationInsightService::OUTPUT_SCHEMA)).to equal(Crm::ConversationInsightService::OUTPUT_SCHEMA)
      expect(Crm::CompanyPrompts.rebrand(Cevico::Company.for(clinic), 'tom CEVICO, paciente')).to eq('tom CEVICO, paciente')
      expect(Crm::NpsSurvey.default_thanks_text(clinic)).to eq(Crm::NpsSurvey::DEFAULT_THANKS_TEXT)
    end

    it 'a voz continua "assistente virtual da CEVICO" e as regras de voz são as de sempre', :aggregate_failures do
      settings = Crm::VoiceAgent::Settings.new(clinic)
      expect(Crm::VoiceAgent::Script.persona_intro(settings)).to eq('a assistente virtual da CEVICO')
      expect(Crm::VoiceAgent::Script.voice_rules(clinic)).to equal(Crm::VoiceAgent::Script::VOICE_RULES)
      expect(Crm::VoiceAgent::Script.voice_tools(clinic)).to eq(Crm::VoiceAgent::Script::VOICE_TOOLS)
      expect(Crm::VoiceAgent::Script.default_partner_message(settings)).to include('A CEVICO agradece')
    end
  end

  describe 'ótica: roteiro genérico da empresa' do
    it 'monta o Roteiro com o nome, as lojas, o que oferece e o vocabulário', :aggregate_failures do
      text = Crm::CevicoScript.text(otica)
      expect(text).to start_with('ROTEIRO DA SUA ÓTICA 1')
      Crm::CevicoScript::SECTIONS.each { |sec| expect(text).to include("== #{sec['title'].upcase} ==") }
      expect(text).to include('Você é a Ana, assistente virtual da Sua Ótica')
      expect(text).to include('LOJAS').and include('Loja Moema — Al. dos Anapurus, 100 — tel. 11999990000').and include('Loja Tatuapé')
      expect(text).to include('óculos de grau, lentes de contato e óculos de sol')
      expect(text).to include('Tom: leve e próximo')
      expect(text).to include('clientes pelo WhatsApp da ótica')
      expect(text).not_to include('Guilherme')
      expect(text).not_to include('Gemelli')
      expect(text).not_to include('{{TABELA_DE_PRECOS}}')
      expect(text).not_to include('REGRA FIXA DE VALORES') # lente fácica não existe numa ótica
    end

    it 'as etapas são as genéricas (boas-vindas → necessidade → oferta → loja → agendar → pós-venda)', :aggregate_failures do
      sales = Crm::CevicoScript.stage_prompt(otica, 'atendente_agendamento')
      expect(sales).to include('BOAS-VINDAS').and include('ENTENDER A NECESSIDADE').and include('APRESENTAR O QUE A EMPRESA OFERECE')
      expect(sales).to include('CONVIDAR PARA A LOJA').and include('AGENDAR / CONFIRMAR').and include('PÓS-VENDA')
      expect(sales).to include('Loja Moema ou Loja Tatuapé')
      expect(Crm::CevicoScript.stage_prompt(otica, 'voice')).to include('Foi a Sua Ótica que ligou')
      expect(Crm::CevicoScript.stage_prompt(otica, 'voice_inbound')).to include('ligou para o número da Sua Ótica')
      expect(Crm::CevicoScript.stage_prompt(otica, 'atendente_pos_op')).to include('PÓS-VENDA')
    end

    it 'o texto do admin vence o genérico e a tela mostra o padrão certo', :aggregate_failures do
      CrmSetting.find_by(account: otica).update!(ai_config: { 'script' => { 'persona' => 'Você é a Bia, da Sua Ótica.' } })
      sections = Crm::CevicoScript.sections(otica).index_by { |s| s['key'] }
      expect(sections['persona']['text']).to eq('Você é a Bia, da Sua Ótica.')
      expect(sections['persona']['default']).to include('assistente virtual da Sua Ótica')
      expect(sections['official_data']['custom']).to be(false)
      expect(Crm::CevicoScript.text(otica)).to include('Você é a Bia')
    end

    it 'os prompts dos agentes viram os genéricos da empresa', :aggregate_failures do
      service = Crm::ConversationInsightService.allocate
      service.instance_variable_set(:@account, otica)
      prompt = service.send(:default_system_prompt)
      expect(prompt).to include('conversas de atendimento da Sua Ótica').and include('Empresa: Sua Ótica (ótica).')
      expect(prompt).to include('Loja Moema').and include('{{TABELA_DE_PRECOS}}')
      expect(prompt).not_to include('Gemelli')
      expect(service.send(:system_prompt)).not_to include('{{TABELA_DE_PRECOS}}')
      schema = service.send(:company_schema, Crm::ConversationInsightService::OUTPUT_SCHEMA)
      expect(schema.dig(:properties, :etapa_do_script, :description)).to eq('Etapa do roteiro da Sua Ótica em que a conversa está')
      expect(schema.dig(:properties, :interesse, :description)).to include('cliente')

      expect(Crm::CompanyPrompts.instagram(Cevico::Company.for(otica))).to include('a Ana, assistente virtual da Sua Ótica')
      expect(Crm::CompanyPrompts.comments(Cevico::Company.for(otica))).to include('Instagram e Facebook da Sua Ótica')
      expect(Crm::CompanyPrompts.mentor(Cevico::Company.for(otica))).to include('Mentor do Time da Sua Ótica')
      expect(Crm::CompanyPrompts.copywriter(Cevico::Company.for(otica))).to include('copywriter sênior da Sua Ótica')
      expect(Crm::NpsSurvey.default_thanks_text(otica)).to include('atendimento na Sua Ótica')
    end

    it 'a voz usa o assistente da empresa quando a persona da Integração está vazia', :aggregate_failures do
      settings = Crm::VoiceAgent::Settings.new(otica)
      expect(Crm::VoiceAgent::Script.persona_intro(settings)).to eq('a Ana, assistente virtual da Sua Ótica')
      expect(Crm::VoiceAgent::Script.default_partner_message(settings)).to include('A Sua Ótica agradece')
      built = Crm::VoiceAgent::Script.build(otica, settings)
      expect(built).to start_with('ROTEIRO DA SUA ÓTICA')
      expect(built).to include('a equipe da Sua Ótica acompanha').and include('(quando foi a Sua Ótica que ligou)')
      expect(built).not_to include('Doutor Gustavo')

      CrmSetting.find_by(account: otica).update!(ai_config: { 'voice' => { 'persona_name' => 'Léo', 'persona_gender' => 'm' } })
      expect(Crm::VoiceAgent::Script.persona_intro(Crm::VoiceAgent::Settings.new(otica))).to eq('o Léo, assistente virtual da Sua Ótica')
    end
  end
end
