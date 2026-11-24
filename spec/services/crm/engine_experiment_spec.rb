require 'rails_helper'

# 🧪 item 400 (22/11): teste A/B de motor do atendente (variante A × B por caixa
# ou por sorteio) + placar de conversão e custo. A OpenAI é simulada (WebMock).
# 🧪 item 403 (23/11): a variante passa a ser PROMPT + MOTOR (Roteiro 2 na B),
# o placar ganha o funil até a cirurgia, a conta da confiança e o histórico.
RSpec.describe Crm::EngineExperiment do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox_a) { create(:inbox, account: account) }
  let(:inbox_b) { create(:inbox, account: account) }
  let(:inbox_split) { create(:inbox, account: account) }
  let(:test_id) { '2026-11-22T10:00:00Z' }
  let(:experiment) do
    { 'enabled' => true, 'model_b' => 'gpt-6.2-sol', 'started_at' => test_id,
      'inboxes' => { inbox_b.id.to_s => 'b', inbox_split.id.to_s => 'split' } }
  end
  let(:agent_cfg) do
    { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox_a.id, inbox_b.id, inbox_split.id], 'no_card' => true, 'ab' => experiment }
  end
  let(:ai_config) { { 'api_key' => 'sk-ant-teste', 'openai_api_key' => 'sk-openai-teste', 'agents' => { 'atendente_agendamento' => agent_cfg } } }
  let!(:settings) { CrmSetting.create!(account: account, ai_config: ai_config) }

  def conversation_in(inbox)
    contact = create(:contact, account: account)
    create(:conversation, account: account, inbox: inbox, contact: contact)
  end

  def track(conversation, arm, event)
    described_class.track!(conversation, 'atendente_agendamento', agent_cfg, arm, event)
  end

  describe 'qual variante atende a conversa' do
    it 'sem teste ligado não há variante', :aggregate_failures do
      conversation = conversation_in(inbox_b)
      expect(described_class.arm_for(conversation, 'atendente_agendamento', agent_cfg.except('ab'))).to be_nil
      expect(described_class.arm_for(conversation, 'atendente_agendamento', agent_cfg.merge('ab' => experiment.merge('enabled' => false)))).to be_nil
    end

    it 'a caixa decide: B na caixa marcada, A em todas as outras', :aggregate_failures do
      expect(described_class.arm_for(conversation_in(inbox_b), 'atendente_agendamento', agent_cfg)).to eq('b')
      expect(described_class.arm_for(conversation_in(inbox_a), 'atendente_agendamento', agent_cfg)).to eq('a')
    end

    it 'no sorteio a conversa fica na MESMA variante e as duas recebem conversas', :aggregate_failures do
      conversations = Array.new(40) { conversation_in(inbox_split) }
      first = conversations.map { |c| described_class.arm_for(c, 'atendente_agendamento', agent_cfg) }
      second = conversations.map { |c| described_class.arm_for(c, 'atendente_agendamento', agent_cfg) }

      expect(second).to eq(first)
      expect(first.tally.keys).to match_array(%w[a b])
      expect(first.count('b')).to be_between(8, 32)
    end

    it 'no sorteio, quem já foi carimbado segue na variante do carimbo' do
      conversation = conversation_in(inbox_split)
      other = described_class.draw(experiment, conversation) == 'a' ? 'b' : 'a'
      track(conversation, other, 'reply' => true)

      expect(described_class.arm_for(conversation.reload, 'atendente_agendamento', agent_cfg)).to eq(other)
    end
  end

  describe 'o atendente usa o motor da variante' do
    let(:url) { Crm::LlmEngines::OpenaiResponses::URL }
    let(:final_hash) do
      { mensagens: ['Oi!'], etapa: 'recepcao', agendar: false,
        agendamento: { nome: '', telefone: '', dia: '', hora: '', unidade: 'paulista', procedimento: '', para_outra_pessoa: false },
        cancelar: false, pausar: false, chamar_humano: false, leitura: 'primeiro contato' }
    end
    let(:openai_body) do
      { 'status' => 'completed', 'usage' => { 'input_tokens' => 1000, 'output_tokens' => 100 },
        'output' => [{ 'type' => 'message', 'role' => 'assistant', 'content' => [{ 'type' => 'output_text', 'text' => final_hash.to_json }] }] }
    end

    def service_for(conversation, **)
      create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: 'oi')
      Crm::ResponderAgentService.new(conversation: conversation, agent_key: 'atendente_agendamento', **)
    end

    it 'variante B chama o ChatGPT e soma o custo da resposta', :aggregate_failures do
      stub_request(:post, url).to_return(status: 200, body: openai_body.to_json, headers: { 'Content-Type' => 'application/json' })
      service = service_for(conversation_in(inbox_b), live: true)

      result = service.call
      expect(result[:modelo]).to eq('gpt-6.2-sol')
      expect(service.experiment_arm).to eq('b')
      # 1000 de entrada × US$ 2 + 100 de saída × US$ 10, por milhão
      expect(service.spent_usd).to be_within(0.0000001).of(0.003)
    end

    it 'variante A segue no modelo do cartão e não encosta na OpenAI', :aggregate_failures do
      service = service_for(conversation_in(inbox_a), live: true)

      expect(service.experiment_arm).to eq('a')
      expect(service.send(:model)).to eq('claude-sonnet-5')
      expect(service.send(:openai_engine?)).to be(false)
    end

    it 'variante B também pode ser outro modelo do Claude' do
      settings.update!(ai_config: ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'ab' => { 'model_b' => 'claude-haiku-4-5' } } }))

      expect(service_for(conversation_in(inbox_b), live: true).send(:model)).to eq('claude-haiku-4-5')
    end

    it 'sem a chave da OpenAI a conversa fica FORA do teste e segue no modelo do cartão', :aggregate_failures do
      settings.update!(ai_config: ai_config.except('openai_api_key'))
      service = service_for(conversation_in(inbox_b), live: true)

      expect(service.experiment_arm).to be_nil
      expect(service.send(:model)).to eq('claude-sonnet-5')
    end

    it 'o 🧪 Testar agente não entra no teste' do
      expect(service_for(conversation_in(inbox_b), simulation: true).experiment_arm).to be_nil
    end
  end

  describe 'placar' do
    it 'soma conversas, respostas, custo, agendamentos e quem chamou a equipe por variante', :aggregate_failures do
      a1 = conversation_in(inbox_a)
      a2 = conversation_in(inbox_a)
      b1 = conversation_in(inbox_b)
      track(a1, 'a', 'cost_usd' => 0.02, 'model' => 'claude-sonnet-5')
      track(a1, 'a', 'reply' => true)
      track(a1, 'a', 'cost_usd' => 0.01, 'model' => 'claude-sonnet-5')
      track(a1, 'a', 'reply' => true, 'booked' => true)
      track(a2, 'a', 'cost_usd' => 0.03, 'model' => 'claude-sonnet-5', 'error' => true)
      track(b1, 'b', 'cost_usd' => 0.004, 'model' => 'gpt-6.2-sol', 'fallback' => true)
      track(b1, 'b', 'reply' => true, 'handoff' => true)
      # a equipe marcou a consulta do paciente da variante B depois que ele entrou no teste
      account.tasks.create!(title: 'Consulta', task_type: 'consulta', due_at: 2.days.from_now, unit: 'paulista',
                            contact_id: b1.contact_id, creator: admin)

      report = described_class.report(account, 'atendente_agendamento')
      a, b = report[:arms]
      expect(a).to include(arm: 'a', model: 'claude-sonnet-5', conversas: 1, respostas: 2, agendou: 1, taxa_agendou: 100.0, erros: 1)
      expect(a[:custo_usd]).to be_within(0.00001).of(0.06)
      expect(a[:custo_por_conversa_usd]).to be_within(0.00001).of(0.06)
      expect(b).to include(arm: 'b', model: 'gpt-6.2-sol', conversas: 1, respostas: 1, agendou: 0, humano: 1, reservas: 1, com_consulta: 1)
      expect(b[:custo_por_consulta_usd]).to be_within(0.00001).of(0.004)
      expect(report[:verdict]).to eq(status: 'cedo', missing: 99)
    end

    it 'zerar o placar (started_at novo) deixa os carimbos antigos de fora' do
      track(conversation_in(inbox_b), 'b', 'reply' => true, 'cost_usd' => 0.01)
      restarted = { 'agents' => { 'atendente_agendamento' => { 'ab' => { 'started_at' => '2026-12-01T00:00:00Z' } } } }
      settings.update!(ai_config: ai_config.deep_merge(restarted))

      expect(described_class.report(account, 'atendente_agendamento')[:arms].sum { |arm| arm[:conversas] }).to eq(0)
    end

    it 'conversa que viu os dois motores sai do placar', :aggregate_failures do
      conversation = conversation_in(inbox_b)
      track(conversation, 'b', 'reply' => true)
      track(conversation, 'a', 'reply' => true)

      report = described_class.report(account, 'atendente_agendamento')
      expect(report[:mixed]).to eq(1)
      expect(report[:arms].sum { |arm| arm[:conversas] }).to eq(0)
    end

    it 'só declara vencedor com amostra mínima e diferença que o acaso não explica', :aggregate_failures do
      arm = ->(key, total, hits) { { arm: key, conversas: total, com_consulta: hits } }

      expect(described_class.verdict([arm.call('a', 99, 10), arm.call('b', 500, 200)])).to include(status: 'cedo', missing: 1)
      expect(described_class.verdict([arm.call('a', 200, 20), arm.call('b', 200, 24)])).to include(status: 'empate')
      expect(described_class.verdict([arm.call('a', 200, 20), arm.call('b', 200, 44)])).to include(status: 'b')
      expect(described_class.verdict([arm.call('a', 200, 44), arm.call('b', 200, 20)])).to include(status: 'a')
    end
  end

  describe 'teste de PROMPT (item 403): a B lê o Roteiro 2 com o mesmo motor' do
    let(:experiment) do
      { 'enabled' => true, 'script_b' => 'v2', 'started_at' => test_id, 'inboxes' => { inbox_b.id.to_s => 'b' } }
    end

    def service_for(conversation)
      create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: 'oi')
      Crm::ResponderAgentService.new(conversation: conversation, agent_key: 'atendente_agendamento', live: true)
    end

    it 'vale como teste mesmo sem modelo na B, e o tipo é "prompt"', :aggregate_failures do
      expect(described_class.active(agent_cfg)).to be_present
      expect(described_class.kind(experiment, 'claude-sonnet-5')).to eq('prompt')
      expect(described_class.kind(experiment.merge('model_b' => 'gpt-6.2-sol'), 'claude-sonnet-5')).to eq('ambos')
      expect(described_class.kind({ 'model_b' => 'gpt-6.2-sol' }, 'claude-sonnet-5')).to eq('motor')
    end

    it 'B igual à A (mesmo Roteiro, sem outro motor) não é teste' do
      expect(described_class.active(agent_cfg.merge('ab' => experiment.merge('script_b' => 'v1')))).to be_nil
    end

    it 'a conversa da B lê o Roteiro 2 no motor do cartão; a da A segue no Roteiro 1', :aggregate_failures do
      in_b = service_for(conversation_in(inbox_b))
      in_a = service_for(conversation_in(inbox_a))

      expect(in_b.experiment_arm).to eq('b')
      expect(in_b.script_version).to eq('v2')
      expect(in_b.system_prompt).to include('ROTEIRO CEVICO 2')
      expect(in_b.send(:model)).to eq('claude-sonnet-5')
      expect(in_a.script_version).to eq('v1')
      expect(in_a.system_prompt).to include('ROTEIRO CEVICO 1')
    end

    it 'o carimbo guarda o Roteiro que a conversa leu' do
      conversation = conversation_in(inbox_b)
      track(conversation, 'b', 'reply' => true)

      expect(conversation.reload.additional_attributes.dig('cevico_ia_ab', 'atendente_agendamento')).to include('arm' => 'b', 'script' => 'v2')
    end

    it 'a impressão digital muda quando o texto do Roteiro 2 é editado', :aggregate_failures do
      before = described_class.digests(account, 'atendente_agendamento', experiment)
      settings.update!(ai_config: settings.ai_config.merge('script_v2' => { Crm::CevicoScript::SECTIONS.first['key'] => 'Texto novo da B' }))
      after = described_class.digests(account, 'atendente_agendamento', experiment)

      expect(after['a']).to eq(before['a'])
      expect(after['b']).not_to eq(before['b'])
    end
  end

  describe 'funil, confiança e histórico (item 403)' do
    it 'lê na Agenda até onde o paciente foi e quem respondeu de volta', :aggregate_failures do
      a1 = conversation_in(inbox_a)
      b1 = conversation_in(inbox_b)
      b2 = conversation_in(inbox_b)
      [a1, b1, b2].each { |conversation| track(conversation, conversation == a1 ? 'a' : 'b', 'reply' => true, 'cost_usd' => 0.01) }
      # o paciente da B respondeu de volta, marcou, compareceu com indicação e marcou a cirurgia
      create(:message, account: account, inbox: inbox_b, conversation: b1, message_type: :incoming, content: 'quero sim',
                       created_at: 1.minute.from_now)
      account.tasks.create!(title: 'Consulta', task_type: 'consulta', due_at: 2.days.from_now, unit: 'paulista', contact_id: b1.contact_id,
                            creator: admin, attendance: 'attended', surgery_indication: 'indicated')
      account.tasks.create!(title: 'Cirurgia', task_type: 'cirurgia', due_at: 9.days.from_now, unit: 'paulista', contact_id: b1.contact_id,
                            creator: admin)
      # consulta cancelada não conta
      account.tasks.create!(title: 'Consulta', task_type: 'consulta', due_at: 2.days.from_now, unit: 'paulista', contact_id: a1.contact_id,
                            creator: admin, canceled_at: Time.current)

      report = described_class.report(account, 'atendente_agendamento')
      a, b = report[:arms]
      expect(a).to include(conversas: 1, respondeu: 0, com_consulta: 0, compareceu: 0, cirurgia: 0)
      expect(b).to include(conversas: 2, respondeu: 1, taxa_respondeu: 50.0, com_consulta: 1, taxa_consulta: 50.0,
                           compareceu: 1, indicacao: 1, cirurgia: 1)
      expect(b[:custo_por_comparecimento_usd]).to be_within(0.00001).of(0.02)
      expect(report[:daily].sum { |row| row[:b]['conversas'] }).to eq(2)
      expect(report[:daily].sum { |row| row[:b]['consultas'] }).to eq(1)
      expect(report[:stats]).to include(:chance_b, :needed, :pace_per_day)
      expect(report[:projection]).to include(:conversas_mes, :extra_consultas)
    end

    it 'a chance da B sobe com a diferença e a amostra pedida cai', :aggregate_failures do
      arm = ->(key, total, hits) { { arm: key, conversas: total, com_consulta: hits } }
      tie = described_class.stats_for([arm.call('a', 200, 20), arm.call('b', 200, 20)], 10)
      ahead = described_class.stats_for([arm.call('a', 200, 20), arm.call('b', 200, 44)], 10)
      slight = described_class.stats_for([arm.call('a', 200, 20), arm.call('b', 200, 24)], 10)

      expect(tie).to include(chance_b: 50.0, needed: nil, days_left: nil)
      expect(ahead[:chance_b]).to be > 99
      expect(ahead[:missing]).to eq(0)
      expect(slight[:chance_b]).to be_between(60, 90)
      expect(slight[:needed]).to be > 200
      expect(slight[:days_left]).to be_positive
    end

    it 'a conta da decisão projeta o mês inteiro em cada variante', :aggregate_failures do
      arms = [{ arm: 'a', conversas: 100, com_consulta: 10, custo_usd: 5.0 }, { arm: 'b', conversas: 100, com_consulta: 15, custo_usd: 8.0 }]
      projection = described_class.projection(arms, 10)

      expect(projection[:conversas_mes]).to eq(600)
      expect(projection[:a]).to eq(custo_usd: 30.0, consultas: 60.0)
      expect(projection[:b]).to eq(custo_usd: 48.0, consultas: 90.0)
      expect(projection).to include(extra_custo_usd: 18.0, extra_consultas: 30.0, custo_por_consulta_extra_usd: 0.6)
    end

    it 'o histórico guarda a ficha do teste encerrado, a mais nova na frente e sem repetir', :aggregate_failures do
      entry = described_class.history_entry(experiment.merge('name' => 'Sol contra Sonnet'), 'atendente_agendamento', agent_cfg,
                                            by: 'Guilherme', decision: 'b')
      list = described_class.push_history(agent_cfg.merge('ab_history' => [{ 'id' => 'antigo' }, { 'id' => test_id }]), entry)

      expect(entry).to include('id' => test_id, 'kind' => 'motor', 'model_a' => 'claude-sonnet-5', 'model_b' => 'gpt-6.2-sol',
                               'script_b' => 'v1', 'decision' => 'b', 'name' => 'Sol contra Sonnet', 'ended_by' => 'Guilherme')
      expect(list.pluck('id')).to eq([test_id, 'antigo'])
    end

    it 'relê um teste do histórico pelo id', :aggregate_failures do
      track(conversation_in(inbox_b), 'b', 'reply' => true)
      restarted = { 'agents' => { 'atendente_agendamento' => { 'ab' => { 'started_at' => '2026-12-01T00:00:00Z' } } } }
      settings.update!(ai_config: ai_config.deep_merge(restarted))

      expect(described_class.report(account, 'atendente_agendamento')[:arms].sum { |row| row[:conversas] }).to eq(0)
      expect(described_class.report(account, 'atendente_agendamento', test_id)[:arms].sum { |row| row[:conversas] }).to eq(1)
    end
  end

  describe 'no job (ao vivo)' do
    let(:conversation) { conversation_in(inbox_b) }
    let(:incoming) do
      create(:message, account: account, inbox: inbox_b, conversation: conversation, message_type: :incoming, content: 'oi, quero fazer refrativa')
    end
    let(:reply) do
      { mensagens: ['Olá!'], etapa: 'recepcao', agendar: false, agendamento: {}, pausar: false, chamar_humano: true,
        leitura: 'primeiro contato', modelo: 'gpt-6.2-sol' }
    end

    before { stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true) }

    it 'carimba a conversa com variante, modelo, custo e resposta', :aggregate_failures do
      service = instance_double(Crm::ResponderAgentService, call: reply, experiment_arm: 'b', spent_usd: 0.0042, script_version: 'v2')
      allow(Crm::ResponderAgentService).to receive(:new).and_return(service)

      Crm::ResponderAgentJob.perform_now(conversation.id, incoming.id, 'atendente_agendamento')

      stamp = conversation.reload.additional_attributes.dig('cevico_ia_ab', 'atendente_agendamento')
      expect(stamp).to include('test' => test_id, 'arm' => 'b', 'model' => 'gpt-6.2-sol', 'respostas' => 1)
      expect(stamp['custo_usd']).to be_within(0.000001).of(0.0042)
      expect(stamp['humano_at']).to be_present
      # 🧾 item 413: o registro permanente (com ou sem teste) soma a mesma resposta
      usage = conversation.reload.additional_attributes['cevico_ia_uso']
      expect(usage).to include('chamadas' => 1, 'respostas' => 1, 'roteiros' => { 'v2' => 1 },
                               'modelos' => { 'gpt-6.2-sol' => { 'n' => 1, 'usd' => 0.0042 } })
      expect(usage['humano_at']).to be_present
    end
  end
end
