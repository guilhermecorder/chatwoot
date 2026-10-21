require 'rails_helper'

# 🔒 Rodada 4 da auditoria — "Dados que não se perdem" (achados #102, #81 e
# RESIL-3): tudo o que grava o ai_config passa pelo gravador travado da casa
# (Cevico::SettingMerge / Crm::AgentState) relendo a config fresca. O Radar de
# Oportunidades, que demora minutos, não apaga mais os avisos que entraram
# na lista enquanto a IA rodava.
RSpec.describe 'Rodada 4 — estado dos agentes no ai_config sob trava' do # rubocop:disable RSpec/DescribeClass
  let(:described_class) { Crm::OpportunityRadarService }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:ai_config) do
    { 'api_key' => 'sk-teste',
      'agents' => { 'opportunity' => { 'enabled' => true, 'watchers' => [{ 'stage_id' => 1 }] } },
      'opportunity_state' => { 'alerts' => [], 'manual_log' => [{ 'action' => 'ativado' }] } }
  end
  let!(:settings) { CrmSetting.create!(account: account, ai_config: ai_config) }
  let(:service) { described_class.new(account: account) }
  let(:task) do
    account.tasks.create!(title: 'Consulta: Maísa Teste', task_type: 'consulta', due_at: 1.day.from_now, unit: 'tatuape',
                          phone: '+5511988887777', creator: admin)
  end

  def saved_state
    settings.reload.ai_config['opportunity_state']
  end

  def saved_alerts
    Array(saved_state['alerts'])
  end

  # aviso de ATENÇÃO gravado por um agente de IA no meio da rodada
  def push_agent_alert!
    Crm::AgentAlert.push(account: account, kind: 'agente_cancelou', task: task, conversation: conversation, agent_key: 'atendente_pos')
  end

  before do
    conversation.update!(waiting_since: 30.minutes.ago, status: :open)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'quero marcar')
    allow(service).to receive(:candidate_conversations).and_return([conversation])
  end

  describe '#call (achado #102: o Radar não apaga os avisos dos outros)' do
    it 'aviso de agente gravado ENQUANTO a IA rodava continua na lista ao fim da rodada', :aggregate_failures do
      # a "chamada de IA" demora e, no meio dela, o agente cancela uma consulta
      allow(service).to receive(:analyze) do
        push_agent_alert!
        { 'oportunidade' => true, 'motivo' => 'Pediu horário', 'acao' => 'Ofereça dois horários' }
      end

      result = service.call

      expect(result[:new]).to eq(1)
      kinds = saved_alerts.map { |a| a['kind'] }
      expect(kinds).to include('agente_cancelou')
      expect(saved_alerts.map { |a| a['conversation_id'] }).to include(conversation.display_id)
      expect(saved_alerts.size).to eq(2)
    end

    it 'aviso ATENDIDO durante a rodada não volta, e as outras chaves do estado (manual_log) ficam', :aggregate_failures do
      # outro paciente já tinha aviso do Radar (conversa aberta esperando = aviso ainda válido)
      other = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account, name: 'João'))
      other.update!(waiting_since: 40.minutes.ago, status: :open)
      stale = { 'conversation_id' => other.display_id, 'contact_name' => 'João', 'created_at' => 5.minutes.ago.iso8601 }
      Cevico::SettingMerge.merge_key!(account, :ai_config, 'opportunity_state') { |s| s.merge('alerts' => [stale]) }
      # enquanto a IA analisa a Maria, alguém clica "Atender agora" no aviso do João
      allow(service).to receive(:analyze) do
        Cevico::SettingMerge.merge_key!(account, :ai_config, 'opportunity_state') { |s| s.merge('alerts' => []) }
        { 'oportunidade' => false, 'motivo' => '', 'acao' => '' }
      end

      service.call

      expect(saved_alerts).to be_empty
      expect(saved_state['manual_log']).to eq([{ 'action' => 'ativado' }])
      expect(saved_state['last_run_at']).to be_present
    end

    it 'aviso vencido sai da lista mesmo que ainda esteja no estado fresco', :aggregate_failures do
      old = { 'conversation_id' => 999_999, 'contact_name' => 'Antigo', 'created_at' => 2.days.ago.iso8601 }
      Cevico::SettingMerge.merge_key!(account, :ai_config, 'opportunity_state') { |s| s.merge('alerts' => [old]) }
      allow(service).to receive(:analyze).and_return({ 'oportunidade' => false, 'motivo' => '', 'acao' => '' })

      service.call

      expect(saved_alerts).to be_empty
    end

    it 'aviso vencido REDETECTADO grava a versão nova (não a velha que ainda estava no banco)', :aggregate_failures do
      # a Maria já tinha aviso de 2 dias (vencido, mas ainda gravado) e continua esperando
      old = { 'conversation_id' => conversation.display_id, 'contact_name' => 'Maria Silva', 'motivo' => 'VELHO',
              'created_at' => 2.days.ago.iso8601 }
      Cevico::SettingMerge.merge_key!(account, :ai_config, 'opportunity_state') { |s| s.merge('alerts' => [old]) }
      allow(service).to receive(:analyze).and_return({ 'oportunidade' => true, 'motivo' => 'NOVO', 'acao' => 'Ofereça horários' })

      result = service.call

      expect(result[:new]).to eq(1)
      expect(saved_alerts.size).to eq(1)
      expect(saved_alerts.first).to include('conversation_id' => conversation.display_id, 'motivo' => 'NOVO')
      expect(Time.zone.parse(saved_alerts.first['created_at'])).to be > 1.minute.ago
    end

    it 'aviso extra REGRAVADO durante a rodada (mesma tarefa, depois do TTL) fica com a versão nova', :aggregate_failures do
      # o agente já tinha avisado desta tarefa há 2 dias (vencido); no meio da rodada avisa de novo
      stale = { 'kind' => 'agente_cancelou', 'task_id' => task.id, 'contact_name' => 'Maísa Teste', 'created_at' => 2.days.ago.iso8601 }
      Cevico::SettingMerge.merge_key!(account, :ai_config, 'opportunity_state') { |s| s.merge('alerts' => [stale]) }
      allow(service).to receive(:analyze) do
        push_agent_alert!
        { 'oportunidade' => false, 'motivo' => '', 'acao' => '' }
      end

      service.call

      expect(saved_alerts.size).to eq(1)
      expect(saved_alerts.first).to include('kind' => 'agente_cancelou', 'task_id' => task.id)
      expect(Time.zone.parse(saved_alerts.first['created_at'])).to be > 1.minute.ago
    end

    it 'grava pelo gravador travado da casa (Cevico::SettingMerge), não com update! direto' do
      allow(service).to receive(:analyze).and_return(nil)
      allow(Cevico::SettingMerge).to receive(:merge_key!).and_call_original

      service.call

      expect(Cevico::SettingMerge).to have_received(:merge_key!).with(account, :ai_config, 'opportunity_state')
    end
  end

  describe 'avisos extras sob trava (achado #81)' do
    before { allow(Cevico::SettingMerge).to receive(:merge_key!).and_call_original }

    it 'Crm::Calls::RadarAlert.push grava a ligação perdida pelo gravador travado e substitui a mesma ligação', :aggregate_failures do
      call = Crm::Call.create!(account: account, inbox: inbox, contact: contact, meta_call_id: "wacid.#{SecureRandom.hex(4)}",
                               direction: :inbound, status: :missed, end_reason: 'not_answered', wa_id: '5511999990000',
                               started_at: 5.minutes.ago, ended_at: 4.minutes.ago, simulated: true)

      alert = Crm::Calls::RadarAlert.push(call)
      Crm::Calls::RadarAlert.push(call)

      expect(alert).to include('kind' => 'missed_call', 'call_id' => call.id, 'contact_name' => 'Maria Silva')
      expect(Cevico::SettingMerge).to have_received(:merge_key!).with(account, :ai_config, 'opportunity_state').twice
      expect(saved_alerts.size).to eq(1)
      expect(saved_state['manual_log']).to eq([{ 'action' => 'ativado' }])
    end

    it 'Crm::Journey::RadarAlert.push grava o "não vou" pelo gravador travado', :aggregate_failures do
      journey_message = double(name: 'Lembrete da véspera') # rubocop:disable RSpec/VerifiedDoubles
      send = double(account: account, id: 42, contact: contact, conversation: nil, journey_message: journey_message) # rubocop:disable RSpec/VerifiedDoubles
      message = double(conversation: conversation, content: 'não vou conseguir ir') # rubocop:disable RSpec/VerifiedDoubles

      alert = Crm::Journey::RadarAlert.push(send, message)

      expect(alert).to include('kind' => 'journey_reply', 'send_id' => 42, 'conversation_id' => conversation.display_id)
      expect(Cevico::SettingMerge).to have_received(:merge_key!).with(account, :ai_config, 'opportunity_state')
      expect(saved_alerts.map { |a| a['send_id'] }).to eq([42])
    end

    it 'Crm::AgentAlert.push grava pelo gravador travado e devolve o aviso montado', :aggregate_failures do
      alert = push_agent_alert!

      expect(alert).to include('kind' => 'agente_cancelou', 'task_id' => task.id)
      expect(Cevico::SettingMerge).to have_received(:merge_key!).with(account, :ai_config, 'opportunity_state')
      expect(saved_alerts.map { |a| a['task_id'] }).to eq([task.id])
    end

    # concorrência de verdade: quem grava tem na mão uma foto VELHA da linha e,
    # entre a foto e a gravação, outro escritor salvou um aviso e uma chave nova.
    # A trava relê a linha fresca — nada do outro escritor some.
    describe 'quando outro escritor grava entre a leitura e a gravação' do
      let(:other_alert) { { 'kind' => 'missed_call', 'call_id' => 999, 'created_at' => Time.current.iso8601 } }

      before do
        stale = CrmSetting.find(settings.id) # foto tirada ANTES da outra gravação
        cfg = settings.reload.ai_config
        cfg['opportunity_state'] = cfg['opportunity_state'].merge('alerts' => [other_alert])
        cfg['outra_chave'] = 'gravada no meio'
        settings.update!(ai_config: cfg)
        allow(CrmSetting).to receive(:find_or_create_by!).and_return(stale)
      end

      it 'Crm::AgentAlert.push mantém o aviso e a chave gravados pelo outro', :aggregate_failures do
        push_agent_alert!

        expect(saved_alerts.map { |a| a['kind'] }).to contain_exactly('missed_call', 'agente_cancelou')
        expect(settings.reload.ai_config['outra_chave']).to eq('gravada no meio')
      end

      it 'Crm::Journey::RadarAlert.push mantém o aviso e a chave gravados pelo outro', :aggregate_failures do
        journey_message = double(name: 'Lembrete da véspera') # rubocop:disable RSpec/VerifiedDoubles
        send = double(account: account, id: 42, contact: contact, conversation: nil, journey_message: journey_message) # rubocop:disable RSpec/VerifiedDoubles
        message = double(conversation: conversation, content: 'não vou conseguir ir') # rubocop:disable RSpec/VerifiedDoubles

        Crm::Journey::RadarAlert.push(send, message)

        expect(saved_alerts.map { |a| a['kind'] }).to contain_exactly('missed_call', 'journey_reply')
        expect(settings.reload.ai_config['outra_chave']).to eq('gravada no meio')
      end
    end
  end

  describe 'Crm::InstagramAgentJob#log_event (achado RESIL-3)' do
    it 'registra o evento pelo Crm::AgentState (sob trava), no mesmo formato de antes', :aggregate_failures do
      allow(Crm::AgentState).to receive(:log).and_call_original
      allow(Cevico::SettingMerge).to receive(:merge_key!).and_call_original

      Crm::InstagramAgentJob.new.send(:log_event, account, conversation, 'erro', 'a IA não respondeu')

      expect(Crm::AgentState).to have_received(:log).with(account, 'instagram', 'erro', 'a IA não respondeu',
                                                          contact: 'Maria Silva', conversation_id: conversation.display_id)
      # Crm::AgentState.update também passa pelo gravador único da casa
      expect(Cevico::SettingMerge).to have_received(:merge_key!).with(settings, :ai_config, 'instagram_state')
      event = settings.reload.ai_config.dig('instagram_state', 'events').first
      expect(event).to include('type' => 'erro', 'conversation_id' => conversation.display_id, 'contact' => 'Maria Silva',
                               'note' => 'a IA não respondeu')
      expect(settings.ai_config['api_key']).to eq('sk-teste') # o resto do ai_config continua lá
    end
  end

  describe 'outros estados no ai_config (achado #102, parte 2)' do
    before { allow(Cevico::SettingMerge).to receive(:merge!).and_call_original }

    it 'Crm::ScriptVersion.write_script! e write_stage_prompt! gravam pelo gravador travado', :aggregate_failures do
      script = Crm::ScriptVersion.write_script!(account, { 'persona' => ' Você é a Clara. ', 'inventado' => 'x' })
      prompt = Crm::ScriptVersion.write_stage_prompt!(account, 'atendente_pos', ' Seja breve. ')

      expect(script).to include('persona' => 'Você é a Clara.')
      expect(script).not_to have_key('inventado')
      expect(prompt).to eq('Seja breve.')
      cfg = settings.reload.ai_config
      expect(cfg.dig('script', 'persona')).to eq('Você é a Clara.')
      expect(cfg.dig('agents', 'atendente_pos', 'prompt')).to eq('Seja breve.')
      expect(cfg.dig('agents', 'opportunity', 'enabled')).to be(true) # os agentes vizinhos ficam
      expect(Cevico::SettingMerge).to have_received(:merge!).with(account, :ai_config).twice
    end

    it 'Crm::ObjectionMapService#save_map grava o mapa sob trava sem apagar o resto da config' do
      map = { 'generated_at' => Time.current.iso8601, 'stages' => [] }

      Crm::ObjectionMapService.new(account).send(:save_map, map)

      cfg = settings.reload.ai_config
      expect(cfg.dig('agents', 'sales', 'objection_map')).to eq(map)
      expect(cfg.dig('agents', 'opportunity', 'enabled')).to be(true)
      expect(Cevico::SettingMerge).to have_received(:merge!).with(account, :ai_config)
    end

    it 'Crm::CommentsAgentService#save_state grava só a chave comments_state sob trava', :aggregate_failures do
      allow(Cevico::SettingMerge).to receive(:merge_key!).and_call_original

      Crm::CommentsAgentService.new(account).send(:save_state, { 'c1' => Time.current.iso8601 }, [{ 'type' => 'ok' }])

      cfg = settings.reload.ai_config
      expect(cfg.dig('comments_state', 'handled').keys).to eq(['c1'])
      expect(cfg.dig('comments_state', 'events')).to eq([{ 'type' => 'ok' }])
      expect(cfg['api_key']).to eq('sk-teste')
      expect(Cevico::SettingMerge).to have_received(:merge_key!).with(account, :ai_config, 'comments_state')
    end
  end
end
