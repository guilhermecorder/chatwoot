require 'rails_helper'
require 'rake'

# 🔒 auditoria 10/2026 (#211/#212) — "Portas fechadas": os comandos de TESTE
# (voice_tools, voice_simulate, calls_simulate, wa_agent_simulate,
# creatives_demo_funnel) não podem rodar em produção por engano nem cair em
# paciente de verdade; conversa simulada nunca sai ao vivo.
RSpec.describe 'cevico: comandos de simulação travados fora do desenvolvimento' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:guard) { Cevico::SimulationGuard }
  # ENV de verdade, guardada ANTES de qualquer stub (cada env() parte dela, sem herdar chaves do passo anterior)
  let!(:real_env) { ENV.to_h }

  before do
    Rake::Task.define_task(:environment)
    { 'tasks/cevico_voice' => 'cevico:voice_tools', 'tasks/cevico_calls' => 'cevico:calls_simulate',
      'tasks/cevico_wa_agent' => 'cevico:wa_agent_simulate', 'tasks/cevico_creatives_demo' => 'cevico:creatives_demo_funnel' }.each do |file, task|
      Rake.application.rake_require(file) unless Rake::Task.task_defined?(task)
    end
    %w[cevico:voice_tools cevico:voice_simulate cevico:calls_simulate cevico:calls_end cevico:wa_agent_simulate
       cevico:creatives_demo_funnel].each { |t| Rake::Task[t].reenable }
  end

  # finge que o processo está na VPS (produção)
  def producao!
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
  end

  def env(vars)
    stub_const('ENV', real_env.merge({ 'ACCOUNT_ID' => account.id.to_s }.merge(vars)))
  end

  describe Cevico::SimulationGuard do
    it 'no ambiente local deixa passar sem variável nenhuma e não confere o telefone' do
      contact = create(:contact, account: account, phone_number: '+5511988887777')
      env({})
      expect { guard.check!('cevico:voice_tools') }.not_to raise_error
      expect(guard.phone!(account, contact.phone_number, 'cevico:voice_tools')).to eq('5511988887777')
    end

    it 'fora do local aborta sem CEVICO_SIMULATION_OK=1 e passa com ela', :aggregate_failures do
      producao!
      env({})
      expect { guard.check!('cevico:voice_tools') }.to raise_error(SystemExit, /só roda em desenvolvimento/)
      env('CEVICO_SIMULATION_OK' => '1')
      expect { guard.check!('cevico:voice_tools') }.not_to raise_error
    end

    it 'fora do local recusa CONTACT_ID= e CAMPAIGN_ID= mesmo com a variável de escape', :aggregate_failures do
      producao!
      env('CEVICO_SIMULATION_OK' => '1', 'CONTACT_ID' => '12')
      expect { guard.check!('cevico:calls_simulate') }.to raise_error(SystemExit, /tire CONTACT_ID=/)
      env('CEVICO_SIMULATION_OK' => '1', 'CAMPAIGN_ID' => '1')
      expect { guard.check!('cevico:voice_simulate') }.to raise_error(SystemExit, /tire CAMPAIGN_ID=/)
    end

    it 'fora do local exige PHONE= e recusa número de paciente cadastrado', :aggregate_failures do
      producao!
      paciente = create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511988887777')
      env('CEVICO_SIMULATION_OK' => '1')
      expect { guard.phone!(account, guard::FAKE_PHONE, 'cevico:voice_tools') }.to raise_error(SystemExit, /informe PHONE=/)
      # 8 últimos dígitos iguais = mesma pessoa para o sistema (Task.match_contact)
      env('CEVICO_SIMULATION_OK' => '1', 'PHONE' => '11 98888-7777')
      expect { guard.phone!(account, '11 98888-7777', 'cevico:voice_tools') }.to raise_error(SystemExit, /paciente cadastrado \(##{paciente.id}\)/)
      env('CEVICO_SIMULATION_OK' => '1', 'PHONE' => '5511000000000')
      expect(guard.phone!(account, '5511000000000', 'cevico:voice_tools')).to eq('5511000000000')
    end
  end

  describe 'cevico:voice_tools (#211)' do
    it 'em produção aborta antes de tocar em qualquer ferramenta' do
      producao!
      env({})
      allow(Crm::VoiceAgent::ToolsService).to receive(:new)
      expect { Rake::Task['cevico:voice_tools'].invoke }.to raise_error(SystemExit, /cevico:voice_tools é um comando de TESTE/)
      expect(Crm::VoiceAgent::ToolsService).not_to have_received(:new)
    end

    it 'sem PHONE= usa o número fictício — nunca o 1º paciente da conta', :aggregate_failures do
      create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511988887777')
      tools = instance_double(Crm::VoiceAgent::ToolsService, perform: {})
      allow(Crm::VoiceAgent::ToolsService).to receive(:new).and_return(tools)
      env({})
      expect { Rake::Task['cevico:voice_tools'].invoke }.to output(/buscar_paciente/).to_stdout
      expect(Crm::VoiceAgent::ToolsService).to have_received(:new)
        .with(hash_including(params: hash_including('telefone' => guard::FAKE_PHONE))).at_least(:once)
      expect(Crm::VoiceAgent::ToolsService).not_to have_received(:new)
        .with(hash_including(params: hash_including('telefone' => '5511988887777')))
    end
  end

  describe 'cevico:calls_simulate (#211)' do
    it 'em produção, mesmo com a variável de escape, recusa PHONE= de paciente cadastrado sem criar ligação' do
      producao!
      create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511988887777')
      create(:inbox, account: account)
      allow(Crm::Calls::WebhookService).to receive(:new)
      env('CEVICO_SIMULATION_OK' => '1', 'PHONE' => '5511988887777')
      expect { Rake::Task['cevico:calls_simulate'].invoke }.to raise_error(SystemExit, /paciente cadastrado/)
      expect(Crm::Calls::WebhookService).not_to have_received(:new)
    end

    it 'em produção calls_end também aborta sem a variável (encerraria ligação real)' do
      producao!
      env('CALL_ID' => '1')
      allow(Crm::Call).to receive(:find)
      expect { Rake::Task['cevico:calls_end'].invoke }.to raise_error(SystemExit, /cevico:calls_end é um comando de TESTE/)
      expect(Crm::Call).not_to have_received(:find)
    end
  end

  describe 'cevico:wa_agent_simulate (#212)' do
    let(:inbox) { create(:inbox, account: account) }

    before do
      agent = { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id] }
      CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_agendamento' => agent } })
      allow(Crm::ResponderAgentJob).to receive(:perform_now)
    end

    it 'em produção aborta antes de criar paciente ou conversa', :aggregate_failures do
      producao!
      env({})
      expect { Rake::Task['cevico:wa_agent_simulate'].invoke(account.id.to_s) }
        .to raise_error(SystemExit, /cevico:wa_agent_simulate é um comando de TESTE/)
      expect(account.contacts.count).to eq(0)
      expect(Crm::ResponderAgentJob).not_to have_received(:perform_now)
    end

    it 'cria o paciente de teste com telefone claramente inválido (00 depois do DDD) e avisa que é sombra', :aggregate_failures do
      env('MSGS' => 'oi')
      expect { Rake::Task['cevico:wa_agent_simulate'].invoke(account.id.to_s) }.to output(/modo: sombra/).to_stdout
      contact = account.contacts.last
      expect(contact.phone_number).to match(/\A\+551100\d{6}\z/)
      conversation = account.conversations.last
      expect(conversation.additional_attributes['cevico_simulado']).to be(true)
      expect(Crm::ResponderAgentJob).to have_received(:perform_now).with(conversation.id, kind_of(Integer), 'atendente_agendamento')
    end
  end

  describe 'cevico:creatives_demo_funnel (#211)' do
    it 'em produção não cria lead fictício sem a variável, mas o UNDO=1 (limpeza) continua livre', :aggregate_failures do
      producao!
      env({})
      expect { Rake::Task['cevico:creatives_demo_funnel'].invoke }.to raise_error(SystemExit, /creatives_demo_funnel é um comando de TESTE/)
      Rake::Task['cevico:creatives_demo_funnel'].reenable
      env('UNDO' => '1')
      expect { Rake::Task['cevico:creatives_demo_funnel'].invoke }.to output(/0 lead\(s\) de demonstração apagados/).to_stdout
    end
  end

  # o desvio dentro do job: conversa simulada NUNCA roda ao vivo
  describe Crm::ResponderAgentJob do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account, name: 'Paciente Simulado', phone_number: '+551100123456') }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, additional_attributes: { 'cevico_simulado' => true })
    end
    let(:ai_reply) do
      { mensagens: ['Olá! Aqui é o Guilherme, da CEVICO.'], etapa: 'recepcao', agendar: false, agendamento: {},
        pausar: false, chamar_humano: false, leitura: 'primeiro contato' }
    end

    before do
      stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
      create(:user, account: account, role: :administrator)
      agent = { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id] }
      CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_agendamento' => agent } })
      allow(Crm::ResponderAgentService).to receive(:new).and_return(instance_double(Crm::ResponderAgentService, call: ai_reply))
    end

    it 'com o agente AO VIVO, a conversa simulada fica em SOMBRA: nota interna, nenhum balão outgoing', :aggregate_failures do
      expect(described_class.live_mode?({ 'mode' => 'live' })).to be(true) # o agente está mesmo ao vivo
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
      described_class.perform_now(conversation.id, message.id, 'atendente_agendamento')

      expect(Crm::ResponderAgentService).to have_received(:new).with(hash_including(live: false))
      expect(conversation.messages.where(message_type: :outgoing).count).to eq(0)
      note = conversation.messages.where(message_type: :activity).last
      expect(note.additional_attributes.dig('cevico_ia_shadow', 'trigger_message_id')).to eq(message.id)
    end
  end
end
