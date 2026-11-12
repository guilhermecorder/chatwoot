require 'rails_helper'

# 🕶️ 12/11/2026 (LIFE · Atendente do Orçamento): um atendente OBSERVA colunas de outro
# (sombra_stage_ids) e só escreve a nota de sombra, ao lado do dono que responde de verdade.
RSpec.describe Crm::ResponderShadowJob do
  include ActiveJob::TestHelper

  around do |example|
    old = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = old
  end

  before { stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Marcos Lima') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life') }
  let!(:stage_lead) { pipeline.stages.create!(name: 'Novos Contatos', position: 0) }
  let!(:stage_sent) { pipeline.stages.create!(name: 'Orçamento Enviado', position: 1) }
  let(:owner_cfg) { { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id], 'stage_ids' => [stage_lead.id, stage_sent.id] } }
  let(:observer_cfg) do
    { 'enabled' => true, 'mode' => 'shadow', 'inbox_ids' => [inbox.id], 'stage_ids' => [], 'sombra_stage_ids' => [stage_sent.id],
      'nome' => 'Atendente do Orçamento' }
  end
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste',
                                                      'agents' => { 'atendente_agendamento' => owner_cfg, 'atendente_pos' => observer_cfg } })
  end
  let(:ai_reply) do
    { mensagens: ['Maravilha, Marcos!', 'Qual forma de pagamento fica melhor pra você?'], etapa: 'orcamento', agendar: false,
      agendamento: {}, cancelar: false, pausar: false, chamar_humano: false, leitura: 'Cliente disse sim ao orçamento.' }
  end

  def card_in(stage)
    Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: pipeline.id) { |c| c.stage_id = stage.id }
                .update!(stage_id: stage.id)
  end

  def incoming(content = 'sim, quero fazer')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def fire(message)
    CrmListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def stub_ai(result = ai_reply)
    allow(Crm::ResponderAgentService).to receive(:new).and_return(instance_double(Crm::ResponderAgentService, call: result))
  end

  describe 'no CrmListener' do
    it 'coluna observada: o dono recebe o job de sempre E o observador recebe o dele', :aggregate_failures do
      card_in(stage_sent)
      message = incoming
      fire(message)
      expect(Crm::ResponderAgentJob).to have_been_enqueued.with(conversation.id, message.id, 'atendente_agendamento')
      expect(described_class).to have_been_enqueued.with(conversation.id, message.id, 'atendente_pos')
    end

    it 'coluna sem dono: o observador escreve a nota mesmo assim (ninguém responde de verdade)', :aggregate_failures do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'stage_ids' => [stage_lead.id] } }))
      card_in(stage_sent)
      message = incoming
      fire(message)
      expect(Crm::ResponderAgentJob).not_to have_been_enqueued
      expect(described_class).to have_been_enqueued.with(conversation.id, message.id, 'atendente_pos')
    end

    it 'coluna que ele não observa: só o dono', :aggregate_failures do
      card_in(stage_lead)
      fire(incoming)
      expect(Crm::ResponderAgentJob).to have_been_enqueued.with(conversation.id, kind_of(Integer), 'atendente_agendamento')
      expect(described_class).not_to have_been_enqueued
    end

    it 'observador desligado ou de outra caixa: nada' do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_pos' => { 'enabled' => false } }))
      card_in(stage_sent)
      fire(incoming)
      expect(described_class).not_to have_been_enqueued
    end
  end

  describe '#perform' do
    it 'escreve a nota de sombra com o nome da conta e NUNCA fala com o cliente, mesmo marcado ao vivo', :aggregate_failures do
      settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_pos' => { 'mode' => 'live' } }))
      stub_ai
      message = incoming
      expect(Redis::LockManager).not_to receive(:new) # não segura a conversa do dono
      described_class.perform_now(conversation.id, message.id, 'atendente_pos')

      note = conversation.messages.where(message_type: :activity).last
      expect(note.content).to include('🕶️ Sombra · Atendente do Orçamento').and include('1) Maravilha, Marcos!')
      expect(note.additional_attributes['cevico_ia_shadow']).to include('agent' => 'atendente_pos', 'trigger_message_id' => message.id)
      expect(conversation.messages.where(message_type: :outgoing)).to be_empty
      expect(Crm::ResponderAgentService).to have_received(:new).with(hash_including(agent_key: 'atendente_pos', live: false))
      expect(Thread.current[described_class::LABEL_KEY]).to be_nil
    end

    it 'a nota do dono (em sombra) não impede a do observador; a do observador não repete', :aggregate_failures do
      stub_ai
      message = incoming
      Crm::ResponderAgentJob.write_shadow_note!(conversation, 'atendente_agendamento', ai_reply, message.id)
      2.times { described_class.perform_now(conversation.id, message.id, 'atendente_pos') }
      agents = conversation.messages.where(message_type: :activity).map { |m| m.additional_attributes.dig('cevico_ia_shadow', 'agent') }
      expect(agents).to contain_exactly('atendente_agendamento', 'atendente_pos')
    end

    it 'mensagem que já não é a última do cliente: nada' do
      stub_ai
      first = incoming('sim')
      incoming('no cartão')
      expect { described_class.perform_now(conversation.id, first.id, 'atendente_pos') }
        .not_to(change { conversation.messages.where(message_type: :activity).count })
    end
  end
end
