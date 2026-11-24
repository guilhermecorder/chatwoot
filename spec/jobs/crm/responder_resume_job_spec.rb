require 'rails_helper'

# 🔁 23/11 (atendimento sem buraco): camada ATIVA da pausa com prazo — na hora
# marcada confere se a pausa ainda é a mesma e venceu; se venceu, limpa, deixa
# a nota e devolve ao agente a mensagem do paciente que ficou sem resposta.
RSpec.describe Crm::ResponderResumeJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:human) { create(:user, account: account, role: :agent) }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id], 'no_card' => true } }
  let!(:settings) { CrmSetting.create!(account: account, ai_config: { 'agents' => { 'atendente_agendamento' => agent_cfg } }) }
  let(:state_key) { Crm::ResponderAgentJob::STATE_KEY }

  before { stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true) }

  def message(type, minutes_ago:, content: 'oi', sender: nil)
    attrs = { account: account, inbox: inbox, conversation: conversation, message_type: type, content: content,
              created_at: minutes_ago.minutes.ago }
    attrs[:sender] = sender if sender
    create(:message, **attrs)
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

  def handed_back
    have_enqueued_job(Crm::ResponderAgentJob)
  end

  describe 'pausa de quem assumiu (humano_assumiu)' do
    it 'venceu e a última fala é do paciente: limpa a pausa, deixa a nota e devolve a mensagem ao agente', :aggregate_failures do
      message(:outgoing, minutes_ago: 3, sender: human)
      waiting = message(:incoming, minutes_ago: 1, content: 'e o valor?')
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'by' => human.name, 'at' => 3.minutes.ago.iso8601)

      expect { described_class.perform_now(conversation.id) }
        .to have_enqueued_job(Crm::ResponderAgentJob).with(conversation.id, waiting.id, 'atendente_agendamento')
      expect(state).to eq({})
      expect(notes.last).to include('▶️ Atendente IA do WhatsApp religado sozinho').and include('2 min sem mensagem da equipe')
      event = settings.reload.ai_config.dig('atendente_agendamento_state', 'events').first
      expect(event).to include('type' => 'religou', 'conversation_id' => conversation.display_id)
    end

    it 'venceu e a última fala é da equipe: religa (nota) mas não chama o agente', :aggregate_failures do
      message(:incoming, minutes_ago: 5)
      message(:outgoing, minutes_ago: 3, sender: human)
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'at' => 3.minutes.ago.iso8601)

      expect { described_class.perform_now(conversation.id) }.not_to handed_back
      expect(state).to eq({})
      expect(notes.last).to include('religado sozinho')
    end

    it 'a equipe escreveu de novo (hora da pausa renovada): este job sai sem fazer nada', :aggregate_failures do
      message(:incoming, minutes_ago: 1)
      renewed = { 'paused' => true, 'reason' => 'humano_assumiu', 'by' => human.name, 'at' => 30.seconds.ago.iso8601 }
      pause!(renewed)

      expect { described_class.perform_now(conversation.id) }.not_to handed_back
      expect(state).to eq(renewed)
      expect(notes).to be_empty
    end

    it 'prazo 0 na conta: nunca religa sozinha' do
      settings.update!(ai_config: settings.ai_config.merge('responder_resume_after_human_minutes' => 0))
      message(:incoming, minutes_ago: 1)
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'at' => 2.days.ago.iso8601)

      expect { described_class.perform_now(conversation.id) }.not_to(change { state })
    end
  end

  it 'pausa pela chavinha (botao), teto diário e urgência clínica NÃO vencem', :aggregate_failures do
    message(:incoming, minutes_ago: 30)
    [{ 'reason' => 'botao' }, { 'reason' => 'teto_diario' }, { 'reason' => 'chamou_humano', 'urgente' => true },
     { 'reason' => 'humano_assumiu', 'sem_prazo' => true }].each do |extra|
      paused = { 'paused' => true, 'at' => 2.days.ago.iso8601 }.merge(extra)
      pause!(paused)

      expect { described_class.perform_now(conversation.id) }.not_to handed_back
      expect(state).to eq(paused)
    end
    expect(notes).to be_empty
  end

  describe 'pausa da IA que chamou a equipe (chamou_humano)' do
    let!(:answered) { message(:incoming, minutes_ago: 40, content: 'quero falar com alguém') }
    let(:handoff_at) { 39.minutes.ago.iso8601 }

    before do
      pause!('paused' => true, 'reason' => 'chamou_humano', 'agent' => 'atendente_agendamento', 'at' => handoff_at, 'msg' => answered.id)
    end

    it 'paciente escreveu há mais de 10 min e ninguém respondeu: a IA volta com a marca de pedido pendente', :aggregate_failures do
      waiting = message(:incoming, minutes_ago: 11, content: 'tem horário amanhã?')

      expect { described_class.perform_now(conversation.id) }
        .to have_enqueued_job(Crm::ResponderAgentJob).with(conversation.id, waiting.id, 'atendente_agendamento')
      expect(state).not_to include('paused')
      expect(state.dig('handoff_pending', 'at')).to eq(handoff_at)
      expect(Crm::ResponderPause.handoff_pending?(conversation.reload)).to be(true)
      expect(notes.last).to include('voltou a responder sozinho').and include('A tarefa continua aberta')
    end

    it 'paciente escreveu há menos de 10 min: ainda espera a equipe' do
      message(:incoming, minutes_ago: 4, content: 'tem horário amanhã?')

      expect { described_class.perform_now(conversation.id) }.not_to handed_back
      expect(state).to include('paused' => true, 'reason' => 'chamou_humano')
    end

    it 'paciente não escreveu depois do pedido: nada muda (a IA não fala sozinha)' do
      expect { described_class.perform_now(conversation.id) }.not_to(change { state })
    end

    it 'pausa antiga sem a marca da mensagem: vale a hora do pedido', :aggregate_failures do
      pause!('paused' => true, 'reason' => 'chamou_humano', 'at' => handoff_at)
      message(:incoming, minutes_ago: 15, content: 'oi?')

      expect { described_class.perform_now(conversation.id) }.to handed_back
      expect(state).not_to include('paused')
    end
  end

  describe 'cercas na hora de devolver ao agente' do
    before do
      message(:incoming, minutes_ago: 1)
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'at' => 5.minutes.ago.iso8601)
    end

    it 'paciente de parceiro (Oftalmofácil) nunca volta para a IA' do
      contact.update!(additional_attributes: { 'parceiro' => 'CLINICA VISAO NORTE' })

      expect { described_class.perform_now(conversation.id) }.not_to handed_back
    end

    it 'coluna sem agente dono fica com a equipe' do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'no_card' => false } }))

      expect { described_class.perform_now(conversation.id) }.not_to handed_back
    end

    it 'agente em sombra ou conversa resolvida: não devolve', :aggregate_failures do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'shadow' } }))
      expect { described_class.perform_now(conversation.id) }.not_to handed_back

      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'mode' => 'live' } }))
      pause!('paused' => true, 'reason' => 'humano_assumiu', 'at' => 5.minutes.ago.iso8601)
      conversation.update_columns(status: Conversation.statuses[:resolved]) # rubocop:disable Rails/SkipsModelValidations
      expect { described_class.perform_now(conversation.id) }.not_to handed_back
    end
  end

  it 'conversa sem pausa (ou que não existe mais): não faz nada' do
    message(:incoming, minutes_ago: 1)

    expect { described_class.perform_now(conversation.id) }.not_to handed_back
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
