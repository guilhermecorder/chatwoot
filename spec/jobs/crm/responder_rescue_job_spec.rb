require 'rails_helper'

# item 291: paciente que ficou sem resposta volta para o agente
# 🛟 23/11 (resgate que não desiste): janela de 3 min a 23 h, a mesma mensagem
# volta enquanto o motor falhar (uma tentativa a cada 30 min), 15 por rodada
RSpec.describe Crm::ResponderRescueJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id], 'no_card' => true } }
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_agendamento' => agent_cfg } })
  end

  # as marcas do resgate/desfecho (cevico:responder:…) vivem num Redis de
  # mentira por exemplo: SET NX de verdade, sem sobra de uma rodada para a outra
  let(:marks) { {} }

  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    allow(Redis::Alfred).to receive(:set).and_return(true)
    allow(Redis::Alfred).to receive(:set).with(/\Acevico:responder:/, any_args) do |key, value, nx: false, **|
      next false if nx && marks.key?(key)

      marks[key] = value.to_s
      true
    end
    allow(Redis::Alfred).to receive(:get).and_call_original
    allow(Redis::Alfred).to receive(:get).with(/\Acevico:responder:/) { |key| marks[key] }
  end

  def outcome!(message, value)
    marks[format(Crm::ResponderAgentJob::OUTCOME_KEY, id: message.id)] = value
  end

  # o tempo passa: a marca de "uma tentativa a cada 30 min" expira sozinha
  def gap_expired!(message)
    marks.delete(format(described_class::RESCUE_KEY, id: message.id))
  end

  def talk(last:, minutes_ago:, status: :open)
    contact = create(:contact, account: account, phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    at = minutes_ago.minutes.ago
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: last,
                               content: 'Terça feira pela manhã', created_at: at)
    # status por último: mensagem nova do paciente reabre a conversa resolvida
    conversation.update_columns(last_activity_at: at, status: Conversation.statuses[status]) # rubocop:disable Rails/SkipsModelValidations
    [conversation, message]
  end

  def rescued
    have_enqueued_job(Crm::ResponderAgentJob)
  end

  it 'devolve ao agente quem esperava há mais de 3 minutos e registra no card', :aggregate_failures do
    conversation, message = talk(last: :incoming, minutes_ago: 10)

    expect { described_class.perform_now }
      .to have_enqueued_job(Crm::ResponderAgentJob).with(conversation.id, message.id, 'atendente_agendamento')
    event = settings.reload.ai_config.dig('atendente_agendamento_state', 'events').first
    expect(event).to include('type' => 'resgate', 'conversation_id' => conversation.display_id)
  end

  it 'a mesma mensagem não é resgatada duas vezes em menos de 30 min' do
    talk(last: :incoming, minutes_ago: 10)

    expect { 2.times { described_class.perform_now } }.to rescued.exactly(:once)
  end

  describe 'resgate que não desiste (23/11)' do
    it 'pane do motor: espera de horas ainda é resgatada (janela de 3 min até 23 h)', :aggregate_failures do
      conversation, message = talk(last: :incoming, minutes_ago: 22 * 60)
      outcome!(message, 'erro')

      expect { described_class.perform_now }
        .to have_enqueued_job(Crm::ResponderAgentJob).with(conversation.id, message.id, 'atendente_agendamento')
    end

    it 'depois de 2 h só entra quem ficou sem resposta por erro do motor (mensagem antiga nunca tentada fica quieta)' do
      talk(last: :incoming, minutes_ago: 5 * 60)
      _, answered_nothing = talk(last: :incoming, minutes_ago: 6 * 60)
      outcome!(answered_nothing, 'ok')

      expect { described_class.perform_now }.not_to rescued
    end

    it 'a janela é configurável na conta (responder_rescue_max_hours)' do
      settings.update!(ai_config: settings.ai_config.merge('responder_rescue_max_hours' => 2))
      talk(last: :incoming, minutes_ago: 5 * 60)

      expect { described_class.perform_now }.not_to rescued
    end

    it 'tentativa anterior terminou em ERRO do motor: a mesma mensagem volta depois de 30 min', :aggregate_failures do
      _, message = talk(last: :incoming, minutes_ago: 10)
      expect { described_class.perform_now }.to rescued.exactly(:once)

      outcome!(message, 'erro')
      # ainda dentro dos 30 min: espera
      expect { described_class.perform_now }.not_to rescued
      gap_expired!(message)
      expect { described_class.perform_now }.to rescued.exactly(:once)
      # e de novo, enquanto o motor continuar falhando
      gap_expired!(message)
      expect { described_class.perform_now }.to rescued.exactly(:once)
    end

    it 'job que morreu no meio da chamada da IA (desfecho pendente) também volta', :aggregate_failures do
      _, message = talk(last: :incoming, minutes_ago: 10)
      described_class.perform_now
      outcome!(message, 'pendente')
      gap_expired!(message)

      expect { described_class.perform_now }.to rescued.exactly(:once)
    end

    it 'tentativa que terminou bem (ou nem chegou à IA) e não gerou resposta: fica em uma vez só', :aggregate_failures do
      _, answered = talk(last: :incoming, minutes_ago: 10)
      _, silent = talk(last: :incoming, minutes_ago: 12)
      _, misconfigured = talk(last: :incoming, minutes_ago: 14)
      expect { described_class.perform_now }.to rescued.exactly(3).times

      outcome!(answered, 'ok')
      outcome!(misconfigured, 'config')
      [answered, silent, misconfigured].each { |message| gap_expired!(message) }
      expect { described_class.perform_now }.not_to rescued
    end

    it 'no máximo 15 conversas por rodada; o resto sai na rodada seguinte', :aggregate_failures do
      settings.update!(ai_config: settings.ai_config.merge('responder_rescue_per_round' => 2))
      3.times { |i| talk(last: :incoming, minutes_ago: 10 + i) }

      expect(Crm::ResponderPause.setting({}, 'responder_rescue_per_round')).to eq(15)
      expect { described_class.perform_now }.to rescued.exactly(:twice)
      expect { described_class.perform_now }.to rescued.exactly(:once)
      expect { described_class.perform_now }.not_to rescued
    end

    it 'da mais recente para a mais antiga' do
      old_talk, old_message = talk(last: :incoming, minutes_ago: 600)
      outcome!(old_message, 'erro')
      new_talk, = talk(last: :incoming, minutes_ago: 5)

      found = described_class.waiting(account, settings.ai_config['agents']).map { |conversation, _| conversation.id }
      expect(found).to eq([new_talk.id, old_talk.id])
    end

    it 'pausa com prazo VENCIDO não segura o resgate; pausa que ainda vale (ou sem prazo) segura', :aggregate_failures do
      key = Crm::ResponderAgentJob::STATE_KEY
      expired, = talk(last: :incoming, minutes_ago: 10)
      expired.update!(additional_attributes: { key => { 'paused' => true, 'reason' => 'humano_assumiu', 'at' => 12.minutes.ago.iso8601 } })
      handoff, = talk(last: :incoming, minutes_ago: 11)
      handoff.update!(additional_attributes: { key => { 'paused' => true, 'reason' => 'chamou_humano', 'at' => 20.minutes.ago.iso8601 } })
      fresh, = talk(last: :incoming, minutes_ago: 4)
      fresh.update!(additional_attributes: { key => { 'paused' => true, 'reason' => 'chamou_humano', 'at' => 20.minutes.ago.iso8601 } })
      button, = talk(last: :incoming, minutes_ago: 10)
      button.update!(additional_attributes: { key => { 'paused' => true, 'reason' => 'botao', 'at' => 2.days.ago.iso8601 } })

      found = described_class.waiting(account, settings.ai_config['agents']).map { |conversation, _| conversation.id }
      expect(found).to contain_exactly(expired.id, handoff.id)
    end
  end

  it 'não mexe em quem já foi respondido, acabou de escrever, espera há muito tempo ou está resolvido', :aggregate_failures do
    talks = { respondido: talk(last: :outgoing, minutes_ago: 10), recente: talk(last: :incoming, minutes_ago: 1),
              antigo: talk(last: :incoming, minutes_ago: 25 * 60), resolvido: talk(last: :incoming, minutes_ago: 10, status: :resolved) }
    agents = settings.ai_config['agents']
    found = described_class.waiting(account, agents).map { |conversation, _| talks.key(talks.values.find { |c, _| c.id == conversation.id }) }

    expect(found).to eq([])
    expect { described_class.perform_now }.not_to rescued
  end

  # (#100) o job original ainda roda (ou morreu com a trava no Redis): a única
  # vez do resgate não pode ser gasta num job que ia encontrar a conversa travada
  it 'conversa travada por outro job: o resgate não gasta a vez e tenta de novo na próxima rodada', :aggregate_failures do
    talk(last: :incoming, minutes_ago: 10)
    lock = instance_double(Redis::LockManager)
    allow(Redis::LockManager).to receive(:new).and_return(lock)
    allow(lock).to receive(:locked?).and_return(true, false)

    expect { described_class.perform_now }.not_to rescued
    # só a marca do resgate (a criação da conversa no preparo também usa o .set)
    expect(Redis::Alfred).not_to have_received(:set).with(/cevico:responder:rescue/, any_args)
    expect { described_class.perform_now }.to rescued
  end

  it 'respeita a pausa da conversa (humano assumiu)' do
    conversation, = talk(last: :incoming, minutes_ago: 10)
    conversation.update!(additional_attributes: { Crm::ResponderAgentJob::STATE_KEY => { 'paused' => true } })

    expect { described_class.perform_now }.not_to rescued
  end

  it 'em sombra, desligado ou sem a trava do ao vivo não faz nada', :aggregate_failures do
    talk(last: :incoming, minutes_ago: 10)
    settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'shadow' } }))
    expect { described_class.perform_now }.not_to rescued

    settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', false)
    expect { described_class.perform_now }.not_to rescued
  end

  # 🚧 auditoria 10/2026 (#63/#98/#253/#459): o listener deixa o paciente de
  # parceiro sem IA de propósito; o resgate não pode devolver a conversa à IA
  it 'cerca dos parceiros: paciente do Oftalmofácil (etiqueta of_) nunca volta para a IA', :aggregate_failures do
    conversation, = talk(last: :incoming, minutes_ago: 10)
    conversation.contact.add_labels(%w[oftalmofacil of_clinica_parceira])

    expect(described_class.waiting(account, settings.ai_config['agents'])).to eq([])
    expect { described_class.perform_now }.not_to rescued
  end

  it 'cerca dos parceiros: paciente com atributo parceiro também fica de fora' do
    conversation, = talk(last: :incoming, minutes_ago: 10)
    conversation.contact.update!(additional_attributes: { 'parceiro' => 'CLINICA VISAO NORTE' })

    expect { described_class.perform_now }.not_to rescued
  end

  it 'coluna sem agente dono fica com a equipe (não resgata)' do
    settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'no_card' => false } }))
    talk(last: :incoming, minutes_ago: 10)

    expect { described_class.perform_now }.not_to rescued
  end
end
