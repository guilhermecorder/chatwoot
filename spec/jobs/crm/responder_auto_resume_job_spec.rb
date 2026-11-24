require 'rails_helper'

# ⏱️ 13/11/2026: a IA volta sozinha N minutos depois da última mensagem da equipe
RSpec.describe Crm::ResponderAutoResumeJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:user) { create(:user, account: account) }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id], 'no_card' => true } }
  let(:auto) { { 'enabled' => true, 'minutes' => 3 } }
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'auto_resume' => auto,
                                                      'agents' => { 'atendente_agendamento' => agent_cfg } })
  end
  let(:state_key) { Crm::ResponderAgentJob::STATE_KEY }

  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    allow(Redis::Alfred).to receive(:set).and_return(true)
  end

  def paused_talk(reason:, paused_ago:, human_ago: nil, client_after: false, extra: {}) # rubocop:disable Metrics/AbcSize
    contact = create(:contact, account: account, phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'Oi, quero um óculos', created_at: 30.minutes.ago)
    if human_ago
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       sender: user, content: 'Oi! Aqui é a Val', created_at: human_ago.minutes.ago)
    end
    client = if client_after
               create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                content: 'E o preço?', created_at: 1.minute.ago)
             end
    state = { 'paused' => true, 'reason' => reason, 'at' => paused_ago.minutes.ago.iso8601 }.merge(extra)
    conversation.update!(additional_attributes: (conversation.additional_attributes || {}).merge(state_key => state))
    [conversation.reload, client]
  end

  def paused?(conversation)
    conversation.reload.additional_attributes.dig(state_key, 'paused') == true
  end

  it 'religa a IA 3 min depois da última mensagem da equipe e deixa nota', :aggregate_failures do
    conversation, = paused_talk(reason: 'humano_assumiu', paused_ago: 5, human_ago: 5)

    described_class.perform_now
    expect(paused?(conversation)).to be(false)
    expect(conversation.messages.where(private: true).last.content).to include('religado sozinho')
  end

  it 'não religa enquanto a equipe ainda está conversando (última mensagem há menos de 3 min)' do
    conversation, = paused_talk(reason: 'humano_assumiu', paused_ago: 10, human_ago: 2)

    described_class.perform_now
    expect(paused?(conversation)).to be(true)
  end

  it 'religa quem foi desligado pela chavinha ou pelo agente chamando humano', :aggregate_failures do
    botao, = paused_talk(reason: 'botao', paused_ago: 4)
    chamou, = paused_talk(reason: 'chamar_humano', paused_ago: 4)

    described_class.perform_now
    expect(paused?(botao)).to be(false)
    expect(paused?(chamou)).to be(false)
  end

  it 'nunca religa urgência clínica nem teto diário', :aggregate_failures do
    urgente, = paused_talk(reason: 'humano_assumiu', paused_ago: 30, extra: { 'urgente' => true })
    teto, = paused_talk(reason: 'teto_diario', paused_ago: 30)

    described_class.perform_now
    expect(paused?(urgente)).to be(true)
    expect(paused?(teto)).to be(true)
  end

  it 'o cliente escreveu depois da equipe e ninguém respondeu: o agente responde na volta' do
    conversation, client = paused_talk(reason: 'humano_assumiu', paused_ago: 6, human_ago: 6, client_after: true)

    expect { described_class.perform_now }
      .to have_enqueued_job(Crm::ResponderAgentJob).with(conversation.id, client.id, 'atendente_agendamento')
  end

  it 'conta sem auto_resume ligado: nada muda' do
    settings.update!(ai_config: settings.ai_config.merge('auto_resume' => { 'enabled' => false }))
    conversation, = paused_talk(reason: 'humano_assumiu', paused_ago: 30, human_ago: 30)

    described_class.perform_now
    expect(paused?(conversation)).to be(true)
  end

  it 'resume_at diz quando a IA volta (para a chavinha mostrar)' do
    conversation, = paused_talk(reason: 'humano_assumiu', paused_ago: 10, human_ago: 1)
    state = conversation.additional_attributes[state_key]

    expect(described_class.resume_at(conversation, state, 3)).to be_within(5.seconds).of(2.minutes.from_now)
  end

  # ⏱️ 24/11 (Fernando): a partir de "Orçamento Enviado" a IA espera 10 min; antes, os 3 de sempre
  context 'with minutes_pos (10 min a partir do orçamento enviado)' do
    let(:auto) { { 'enabled' => true, 'minutes' => 3, 'minutes_pos' => 10 } }
    let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil LIFE') }
    let!(:stages) do
      ['Orçamento a fazer', 'Orçamento Enviado', 'Negociação'].each_with_index.to_h do |name, i|
        [name, Crm::Stage.create!(pipeline: pipeline, name: name, position: i)]
      end
    end

    def on_stage(conversation, name)
      Crm::Contact.create!(contact: conversation.contact, pipeline: pipeline, stage: stages.fetch(name))
      conversation
    end

    it 'card em "Orçamento Enviado" ou depois: 5 min sem a equipe ainda não religa; 11 min religa', :aggregate_failures do
      enviado = on_stage(paused_talk(reason: 'botao', paused_ago: 5).first, 'Orçamento Enviado')
      negociacao = on_stage(paused_talk(reason: 'humano_assumiu', paused_ago: 11, human_ago: 11).first, 'Negociação')

      described_class.perform_now
      expect(paused?(enviado)).to be(true)
      expect(paused?(negociacao)).to be(false)
      expect(negociacao.messages.where(private: true).last.content).to include('10 min sem mensagem da equipe')
    end

    it 'card antes do orçamento enviado: continuam os 3 min' do
      antes = on_stage(paused_talk(reason: 'botao', paused_ago: 5).first, 'Orçamento a fazer')

      described_class.perform_now
      expect(paused?(antes)).to be(false)
    end

    it 'minutes_for diz os minutos de cada conversa (a chavinha mostra a hora certa)', :aggregate_failures do
      cfg = described_class.config(settings)
      expect(described_class.minutes_for(on_stage(paused_talk(reason: 'botao', paused_ago: 1).first, 'Negociação'), cfg)).to eq(10)
      expect(described_class.minutes_for(paused_talk(reason: 'botao', paused_ago: 1).first, cfg)).to eq(3)
    end
  end
end
