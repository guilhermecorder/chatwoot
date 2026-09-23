require 'rails_helper'

# 🔧 rodada 192: laço de tool use do motor dos respondedores (IA simulada)
RSpec.describe Crm::ResponderAgentService do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tz) { Crm::AgendaSlots::TZ }
  let!(:mother) do
    account.tasks.create!(title: 'Consulta: Maísa Teste', task_type: 'consulta', due_at: tz.now.beginning_of_day + 14.hours,
                          unit: 'paulista', phone: '+5511988887777', creator: admin)
  end
  let(:final_json) do
    { mensagens: ['Achei a consulta da Maísa: hoje às 14:00, na Av. Paulista.'], etapa: 'pos_agendamento', agendar: false,
      agendamento: {}, cancelar: false, pausar: false, chamar_humano: false, leitura: 'buscou a consulta da mãe' }.to_json
  end
  let(:usage) { instance_double(Anthropic::Usage, input_tokens: 10, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 5) }
  let(:tool_use) { instance_double(Anthropic::ToolUseBlock, type: :tool_use, id: 'toolu_1', name: 'buscar_consulta', input: { nome: 'Maísa' }) }
  let(:round1) { instance_double(Anthropic::Message, stop_reason: :tool_use, content: [tool_use], usage: usage) }
  let(:round2) do
    instance_double(Anthropic::Message, stop_reason: :end_turn, content: [instance_double(Anthropic::TextBlock, type: :text, text: final_json)],
                                        usage: usage)
  end
  let(:messages_api) { instance_double(Anthropic::Resources::Messages) }

  before do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_pos' => { 'enabled' => true } } })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'minha mãe Maísa tem consulta hoje?')
  end

  def service(agent_key: 'atendente_pos', live: false)
    svc = described_class.new(conversation: conversation, agent_key: agent_key, live: live)
    allow(svc).to receive(:client).and_return(instance_double(Anthropic::Client, messages: messages_api))
    svc
  end

  it 'executa a ferramenta pedida, devolve o resultado à IA e acrescenta acoes', :aggregate_failures do
    calls = []
    allow(messages_api).to receive(:create) do |**params|
      calls << params
      calls.size == 1 ? round1 : round2
    end

    result = service.call
    expect(result[:mensagens]).to eq(['Achei a consulta da Maísa: hoje às 14:00, na Av. Paulista.'])
    expect(result[:acoes].size).to eq(1)
    expect(result[:acoes].first).to include('ferramenta' => 'buscar_consulta', 'ok' => true)
    expect(result[:acoes].first['resumo']).to include('Maísa Teste')

    expect(calls.size).to eq(2)
    expect(calls.first[:tools].pluck(:name)).to eq(Crm::ResponderTools::NAMES)
    expect(calls.first[:output_config][:format][:type]).to eq('json_schema')
    history = calls.last[:messages]
    expect(history.size).to eq(3)
    expect(history[1]).to eq(role: 'assistant', content: [{ type: 'tool_use', id: 'toolu_1', name: 'buscar_consulta', input: { nome: 'Maísa' } }])
    expect(history[2][:content].first).to include(type: 'tool_result', tool_use_id: 'toolu_1')
    expect(JSON.parse(history[2][:content].first[:content])['consultas'].first).to include('id' => mother.id, 'paciente' => 'Maísa Teste',
                                                                                           'telefone_final' => '7777')
    expect(Crm::AiUsage.where(account: account, agent_key: 'atendente_pos').count).to eq(2)
  end

  # 👂🖼️ item 204: áudio transcrito e imagem lida entram como texto do PACIENTE
  it 'áudio transcrito e imagem lida entram na conversa como texto; sem leitura, o marcador pede para escrever', :aggregate_failures do
    audio_msg = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil)
    audio = audio_msg.attachments.create!(account_id: account.id, file_type: :audio,
                                          file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.ogg'), 'audio/ogg'))
    audio.update!(meta: { 'transcribed_text' => 'quero remarcar a consulta da minha mãe', 'cevico_media' => { 'status' => 'done' } })
    image_msg = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'olha aqui')
    image_msg.attachments.create!(account_id: account.id, file_type: :image,
                                  file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png'))

    calls = []
    allow(messages_api).to receive(:create) do |**params|
      calls << params
      round2
    end
    service.call
    transcript = calls.first[:messages].first[:content]
    expect(transcript).to include('PACIENTE: [áudio transcrito: "quero remarcar a consulta da minha mãe"]')
    expect(transcript).to include('PACIENTE: olha aqui [imagem: não foi possível ler; pergunte ao paciente o que ele enviou]')
  end

  it 'passa do teto de voltas → última chamada sem ferramentas (tool_choice none)' do
    calls = []
    allow(messages_api).to receive(:create) do |**params|
      calls << params
      calls.size <= described_class::MAX_TOOL_ROUNDS ? round1 : round2
    end
    result = service.call
    expect(result[:error]).to be_nil
    expect(calls.size).to eq(described_class::MAX_TOOL_ROUNDS + 1)
    expect(calls.last[:tool_choice]).to eq(type: 'none')
    expect(calls[0..-2].map { |c| c[:tool_choice] }).to all(be_nil)
  end

  it 'agente sem ferramentas (instagram) chama sem tools e devolve acoes vazio', :aggregate_failures do
    settings = CrmSetting.find_by(account: account)
    settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'instagram' => { 'enabled' => true } }))
    allow(messages_api).to receive(:create).and_return(round2)
    result = service(agent_key: 'instagram').call
    expect(result[:acoes]).to eq([])
    expect(messages_api).to have_received(:create).with(hash_excluding(:tools))
  end

  it 'o contexto traz o id da consulta futura do próprio paciente' do
    own = account.tasks.create!(title: 'Consulta: Maria Silva', task_type: 'consulta', due_at: 2.days.from_now, unit: 'tatuape',
                                contact: contact, creator: admin)
    expect(service.send(:context_block)).to include("(id #{own.id})")
  end

  # 21/09: o 🧪 Testar agente funciona com o interruptor DESLIGADO (é para antes de ligar)
  describe 'interruptor desligado' do
    let(:conversation) { create(:conversation, account: account) }

    before do
      settings = CrmSetting.find_or_create_by!(account: account)
      cfg = settings.ai_config || {}
      cfg['api_key'] = 'sk-teste'
      cfg['agents'] = (cfg['agents'] || {}).merge('atendente_agendamento' => { 'enabled' => false })
      settings.update!(ai_config: cfg)
    end

    it 'sem simulation, recusa' do
      result = described_class.new(conversation: conversation, agent_key: 'atendente_agendamento').call
      expect(result[:error]).to eq('Agente desligado.')
    end

    it 'com simulation, passa da trava do interruptor (para antes da IA na conversa vazia)' do
      service = described_class.new(conversation: conversation, agent_key: 'atendente_agendamento', simulation: true)
      allow(service).to receive(:build_transcript).and_return(nil)
      expect(service.call[:error]).to eq('Conversa vazia.')
    end
  end

  # 🧪 22/09: o prompt segue a versão do Roteiro presa à conversa de teste
  describe 'versão do Roteiro' do
    it 'conversa de teste nascida no v2 monta o prompt com o Roteiro v2; conversa real fica no v1', :aggregate_failures do
      conversation.update!(additional_attributes: (conversation.additional_attributes || {}).merge('cevico_simulado' => true,
                                                                                                   'cevico_simulado_script' => 'v2'))
      svc = described_class.new(conversation: conversation, agent_key: 'atendente_agendamento', simulation: true)
      expect(svc.script_version).to eq('v2')
      expect(svc.system_prompt).to include('ROTEIRO CEVICO 2').and include('REGRAS INEGOCIÁVEIS')

      conversation.update!(additional_attributes: {})
      svc = described_class.new(conversation: conversation, agent_key: 'atendente_agendamento')
      expect(svc.script_version).to eq('v1')
      expect(svc.system_prompt).to include('fonte única dos atendentes')
      expect(described_class.new(conversation: conversation, agent_key: 'atendente_agendamento', script_version: 'v2').system_prompt)
        .to include('ROTEIRO CEVICO 2')
    end
  end
end
