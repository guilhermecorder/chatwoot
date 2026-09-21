require 'rails_helper'

# 🗣️ rodada 188: a COLUNA do card decide se o Atendente de Agendamento lê a mensagem
RSpec.describe CrmListener do
  # o ao vivo é trancado por variável de ambiente; aqui destravamos para testar
  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    CrmSetting.create!(account: account, ai_config: { 'agents' => { 'atendente_agendamento' => agent_cfg } })
  end

  include ActiveJob::TestHelper

  # os matchers have_enqueued_job só funcionam com o adapter :test (o ambiente
  # de teste do fork usa outro por padrão)
  around do |example|
    old = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = old
  end

  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage_new) { pipeline.stages.create!(name: 'Novos Contatos', position: 0) }
  let!(:stage_booked) { pipeline.stages.create!(name: 'Agendamento de Consulta', position: 1) }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'shadow', 'inbox_ids' => [inbox.id], 'stage_ids' => [stage_new.id], 'no_card' => true } }

  def fire(message)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def incoming(conv = conversation, content: 'oi')
    create(:message, account: account, inbox: conv.inbox, conversation: conv, message_type: :incoming, content: content)
  end

  it 'sem card no CRM (contato novo) → agenda o job do agente com 12 s de espera' do
    Crm::Contact.where(contact_id: contact.id).delete_all
    expect { fire(incoming) }.to have_enqueued_job(Crm::ResponderAgentJob).with(conversation.id, kind_of(Integer), 'atendente_agendamento')
  end

  it 'card numa coluna do agente → agenda o job' do
    Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: pipeline.id) { |c| c.stage_id = stage_new.id }
    expect { fire(incoming) }.to have_enqueued_job(Crm::ResponderAgentJob)
  end

  it 'coluna do agente B (pós-agendamento) → o job vai para o B, não para o A' do
    CrmSetting.find_by(account: account).update!(ai_config: { 'agents' => {
                                                   'atendente_agendamento' => agent_cfg,
                                                   'atendente_pos' => { 'enabled' => true, 'mode' => 'shadow', 'inbox_ids' => [inbox.id],
                                                                        'stage_ids' => [stage_booked.id] }
                                                 } })
    Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: pipeline.id) { |c| c.stage_id = stage_booked.id }
    expect { fire(incoming) }.to have_enqueued_job(Crm::ResponderAgentJob).with(conversation.id, kind_of(Integer), 'atendente_pos')
  end

  it 'card numa coluna que NÃO é do agente → ninguém responde' do
    Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: pipeline.id) { |c| c.stage_id = stage_booked.id }
    expect { fire(incoming) }.not_to have_enqueued_job(Crm::ResponderAgentJob)
  end

  it 'caixa que não é do agente → nada' do
    other = create(:conversation, account: account, inbox: other_inbox, contact: contact)
    Crm::Contact.where(contact_id: contact.id).delete_all
    expect { fire(incoming(other)) }.not_to have_enqueued_job(Crm::ResponderAgentJob)
  end

  it 'em SOMBRA, resposta humana não pausa nem escreve nota de pausa' do
    human = create(:user, account: account, role: :agent)
    outgoing = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'oi, sou eu',
                                sender: human)
    expect { fire(outgoing) }.not_to(change { conversation.messages.where(message_type: :activity).count })
    expect(conversation.reload.additional_attributes['cevico_atendente_wa']).to be_nil
  end

  # 21/09 ("confira se funciona"): os comandos do card — humano responde = pausa;
  # 👍 = reativa; pausado, o paciente não chega ao agente
  context 'with modo AO VIVO (janela sem restrição)' do
    let(:agent_cfg) do
      { 'enabled' => true, 'mode' => 'live', 'live_days' => [], 'inbox_ids' => [inbox.id], 'stage_ids' => [stage_new.id], 'no_card' => true }
    end
    let(:human) { create(:user, account: account, role: :agent) }

    it 'resposta humana PAUSA o agente nessa conversa e deixa a nota ⏸' do
      outgoing = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'oi, sou eu',
                                  sender: human)
      fire(outgoing)
      expect(conversation.reload.additional_attributes.dig('cevico_atendente_wa', 'paused')).to be(true)
      expect(conversation.messages.where(message_type: :activity).last.content).to include('pausado')
    end

    it 'pausado, a mensagem do paciente NÃO vai para o agente' do
      conversation.update!(additional_attributes: { 'cevico_atendente_wa' => { 'paused' => true } })
      expect { fire(incoming) }.not_to have_enqueued_job(Crm::ResponderAgentJob)
    end

    it '👍 do atendimento REATIVA e deixa a nota ▶️' do
      conversation.update!(additional_attributes: { 'cevico_atendente_wa' => { 'paused' => true } })
      thumbs = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: '👍', sender: human)
      fire(thumbs)
      expect(conversation.reload.additional_attributes['cevico_atendente_wa']).to eq({})
      expect(conversation.messages.where(message_type: :activity).last.content).to include('reativado')
      expect { fire(incoming) }.to have_enqueued_job(Crm::ResponderAgentJob)
    end
  end
end
