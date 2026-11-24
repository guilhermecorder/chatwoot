require 'rails_helper'

# 🔁 23/11 (atendimento sem buraco): modelo do WhatsApp não pausa a IA; a pausa
# de quem assumiu vale N min a partir da ÚLTIMA mensagem da equipe; a pausa da
# IA que chamou a equipe vence se o paciente escreveu e ninguém respondeu.
RSpec.describe CrmListener do
  include ActiveJob::TestHelper

  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    CrmSetting.create!(account: account, ai_config: ai_config)
  end

  # os matchers have_enqueued_job só funcionam com o adapter :test
  around do |example|
    old = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = old
  end

  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:human) { create(:user, account: account, role: :agent) }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'live', 'live_days' => [], 'inbox_ids' => [inbox.id], 'no_card' => true } }
  let(:ai_config) { { 'agents' => { 'atendente_agendamento' => agent_cfg } } }
  let(:state_key) { 'cevico_atendente_wa' }

  def fire(message)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def incoming(content: 'oi', at: Time.current)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content, created_at: at)
  end

  def outgoing(content: 'oi, sou eu', sender: human, **attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: content,
                     sender: sender, **attrs)
  end

  def pause!(state)
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge(state_key => state) }
  end

  def state
    conversation.reload.additional_attributes[state_key]
  end

  def notes
    conversation.messages.where(message_type: :activity).order(:id).pluck(:content)
  end

  # ── item 1: modelo do WhatsApp ───────────────────────────────────────────
  describe 'modelo (template) do WhatsApp enviado em nome de um usuário' do
    let(:template) do
      { 'template_params' => { 'name' => 'confirmacao_cirurgia', 'language' => 'pt_BR', 'processed_params' => { '1' => 'Maria' } } }
    end

    it 'NÃO pausa a IA nem deixa nota (é disparo, não conversa)', :aggregate_failures do
      fire(outgoing(content: 'Prezado(a), boa tarde, tudo bem? Sou a Gabriela...', additional_attributes: template))

      expect(state).to be_blank
      expect(notes).to be_empty
      expect { fire(incoming(content: 'confirmo')) }.to have_enqueued_job(Crm::ResponderAgentJob)
    end

    it 'não renova nem troca uma pausa que já existe' do
      pause!('paused' => true, 'reason' => 'botao', 'by' => 'Vaneide', 'at' => 1.hour.ago.iso8601)

      expect { fire(outgoing(additional_attributes: template)) }.not_to(change { state })
    end

    it 'mensagem comum da mesma pessoa continua pausando' do
      fire(outgoing)

      expect(state).to include('paused' => true, 'reason' => 'humano_assumiu')
    end
  end

  # ── item 2: religar sozinha depois da última mensagem humana ─────────────
  describe 'pausa de quem assumiu (humano_assumiu) com prazo' do
    it 'ao pausar, agenda a conferência para 2 min + 5 s e a nota diz quando a IA volta', :aggregate_failures do
      freeze_time do
        expect { fire(outgoing) }
          .to have_enqueued_job(Crm::ResponderResumeJob).with(conversation.id).at(2.minutes.from_now + 5.seconds)
      end
      expect(state).to include('paused' => true, 'reason' => 'humano_assumiu', 'by' => human.name)
      expect(notes.last).to include('pausado').and include('Volta sozinho 2 min')
    end

    it 'cada mensagem nova da equipe renova a hora da pausa e agenda outra conferência, sem repetir a nota', :aggregate_failures do
      travel_to(10.minutes.ago) { fire(outgoing) }
      first_at = state['at']

      expect { fire(outgoing(content: 'só um instante')) }.to have_enqueued_job(Crm::ResponderResumeJob).with(conversation.id)
      expect(Time.zone.parse(state['at'])).to be > Time.zone.parse(first_at)
      expect(state).to include('paused' => true, 'reason' => 'humano_assumiu')
      expect(notes.size).to eq(1)
    end

    it 'dentro do prazo, a mensagem do paciente NÃO vai para o agente' do
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'at' => 1.minute.ago.iso8601)

      expect { fire(incoming) }.not_to have_enqueued_job(Crm::ResponderAgentJob)
    end

    it 'prazo vencido: a pausa é limpa na hora, fica a nota e a mensagem do paciente vai para o agente', :aggregate_failures do
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'by' => 'Vaneide', 'at' => 3.minutes.ago.iso8601)
      message = incoming

      expect { fire(message) }.to have_enqueued_job(Crm::ResponderAgentJob).with(conversation.id, message.id, 'atendente_agendamento')
      expect(state).to eq({})
      expect(notes.last).to include('religado sozinho').and include('2 min sem mensagem da equipe')
    end

    it 'prazo configurado na conta vale (responder_resume_after_human_minutes)' do
      CrmSetting.find_by(account: account).update!(ai_config: ai_config.merge('responder_resume_after_human_minutes' => 30))
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'at' => 10.minutes.ago.iso8601)

      expect { fire(incoming) }.not_to have_enqueued_job(Crm::ResponderAgentJob)
    end

    context 'with prazo 0 (nunca religa: comportamento antigo)' do
      let(:ai_config) { { 'agents' => { 'atendente_agendamento' => agent_cfg }, 'responder_resume_after_human_minutes' => 0 } }

      it 'não agenda nada, a nota manda usar a chavinha e a pausa antiga continua valendo', :aggregate_failures do
        expect { fire(outgoing) }.not_to have_enqueued_job(Crm::ResponderResumeJob)
        expect(notes.last).to include('chavinha').and include('👍')

        pause!('paused' => true, 'reason' => 'humano_assumiu', 'at' => 3.days.ago.iso8601)
        expect { fire(incoming) }.not_to have_enqueued_job(Crm::ResponderAgentJob)
      end
    end

    it 'pausa pela chavinha (botao) NÃO vence, por mais antiga que seja', :aggregate_failures do
      pause!('paused' => true, 'reason' => 'botao', 'by' => 'Vaneide', 'at' => 3.days.ago.iso8601)

      expect { fire(incoming) }.not_to have_enqueued_job(Crm::ResponderAgentJob)
      expect(state).to include('paused' => true, 'reason' => 'botao')
      # e a mensagem da equipe não troca o motivo nem agenda religar
      expect { fire(outgoing) }.not_to have_enqueued_job(Crm::ResponderResumeJob)
      expect(state).to include('reason' => 'botao')
    end

    it 'quem assume uma URGÊNCIA clínica fica com a conversa: a pausa não tem prazo', :aggregate_failures do
      pause!('paused' => true, 'reason' => 'chamou_humano', 'urgente' => true, 'at' => 1.hour.ago.iso8601)

      expect { fire(outgoing(content: 'vem agora pra clínica')) }.not_to have_enqueued_job(Crm::ResponderResumeJob)
      expect(state).to include('paused' => true, 'reason' => 'humano_assumiu', 'sem_prazo' => true)
      expect(state).not_to include('urgente')

      travel_to(1.hour.from_now) do
        expect { fire(incoming(content: 'ok, estou indo')) }.not_to have_enqueued_job(Crm::ResponderAgentJob)
        # outra mensagem da pessoa não devolve o prazo
        fire(outgoing(content: 'estamos te esperando'))
        expect(state).to include('sem_prazo' => true)
      end
    end
  end

  # ── item 3: a IA chamou a equipe (chamou_humano) ─────────────────────────
  describe 'pausa da IA que chamou a equipe (chamou_humano) com prazo' do
    it 'paciente escreve depois do pedido: fica em silêncio por enquanto e agenda a conferência para 10 min + 5 s', :aggregate_failures do
      answered = incoming(content: 'preciso falar com alguém', at: 20.minutes.ago)
      pause!('paused' => true, 'reason' => 'chamou_humano', 'agent' => 'atendente_agendamento', 'at' => 19.minutes.ago.iso8601,
             'msg' => answered.id)

      freeze_time do
        message = incoming(content: 'tem horário amanhã?')
        expect { fire(message) }
          .to have_enqueued_job(Crm::ResponderResumeJob).with(conversation.id).at(10.minutes.from_now + 5.seconds)
      end
      expect(Crm::ResponderAgentJob).not_to have_been_enqueued
      expect(state).to include('paused' => true, 'reason' => 'chamou_humano')
    end

    it 'paciente escreveu há mais de 10 min e ninguém respondeu: a IA volta, com a marca de pedido pendente e a nota', :aggregate_failures do
      answered = incoming(content: 'preciso falar com alguém', at: 30.minutes.ago)
      handoff_at = 29.minutes.ago.iso8601
      pause!('paused' => true, 'reason' => 'chamou_humano', 'agent' => 'atendente_agendamento', 'at' => handoff_at, 'msg' => answered.id)
      incoming(content: 'tem horário amanhã?', at: 11.minutes.ago)
      message = incoming(content: 'alguém aí?')

      expect { fire(message) }.to have_enqueued_job(Crm::ResponderAgentJob).with(conversation.id, message.id, 'atendente_agendamento')
      expect(state).not_to include('paused')
      expect(state.dig('handoff_pending', 'at')).to eq(handoff_at)
      expect(notes.last).to include('voltou a responder sozinho').and include('10 min')
    end

    it 'sem o paciente escrever depois do pedido, a pausa não vence (a IA não fala sozinha)' do
      answered = incoming(content: 'preciso falar com alguém', at: 3.hours.ago)
      pause!('paused' => true, 'reason' => 'chamou_humano', 'at' => 3.hours.ago.iso8601, 'msg' => answered.id)

      expect(Crm::ResponderPause.due(conversation.reload)).to be_nil
    end

    it 'alguém da equipe responde ao pedido: a pausa vira humano_assumiu e o prazo de 2 min conta dessa mensagem', :aggregate_failures do
      pause!('paused' => true, 'reason' => 'chamou_humano', 'agent' => 'atendente_agendamento', 'at' => 20.minutes.ago.iso8601)

      expect { fire(outgoing(content: 'oi, é a Vaneide')) }.to have_enqueued_job(Crm::ResponderResumeJob).with(conversation.id)
      expect(state).to include('paused' => true, 'reason' => 'humano_assumiu', 'by' => human.name)
      expect { fire(incoming) }.not_to have_enqueued_job(Crm::ResponderAgentJob)
    end

    it 'prazo 0 = nunca volta sozinha', :aggregate_failures do
      CrmSetting.find_by(account: account).update!(ai_config: ai_config.merge('responder_resume_after_handoff_minutes' => 0))
      answered = incoming(at: 3.hours.ago)
      pause!('paused' => true, 'reason' => 'chamou_humano', 'at' => 3.hours.ago.iso8601, 'msg' => answered.id)
      incoming(content: 'oi?', at: 2.hours.ago)

      fire(incoming(content: 'alguém?'))
      expect(Crm::ResponderAgentJob).not_to have_been_enqueued
      expect(Crm::ResponderResumeJob).not_to have_been_enqueued
    end
  end
end
