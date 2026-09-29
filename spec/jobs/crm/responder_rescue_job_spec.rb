require 'rails_helper'

# item 291: paciente que ficou sem resposta volta para o agente (uma vez só)
RSpec.describe Crm::ResponderRescueJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id], 'no_card' => true } }
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_agendamento' => agent_cfg } })
  end

  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    allow(Redis::Alfred).to receive(:set).and_return(true)
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

  it 'a mesma mensagem é resgatada uma vez só' do
    talk(last: :incoming, minutes_ago: 10)
    allow(Redis::Alfred).to receive(:set).and_return(true, false)

    expect { 2.times { described_class.perform_now } }.to rescued.exactly(:once)
  end

  it 'não mexe em quem já foi respondido, acabou de escrever, espera há muito tempo ou está resolvido', :aggregate_failures do
    talks = { respondido: talk(last: :outgoing, minutes_ago: 10), recente: talk(last: :incoming, minutes_ago: 1),
              antigo: talk(last: :incoming, minutes_ago: 300), resolvido: talk(last: :incoming, minutes_ago: 10, status: :resolved) }
    agents = settings.ai_config['agents']
    found = described_class.waiting(account, agents).map { |conversation, _| talks.key(talks.values.find { |c, _| c.id == conversation.id }) }

    expect(found).to eq([])
    expect { described_class.perform_now }.not_to rescued
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

  it 'coluna sem agente dono fica com a equipe (não resgata)' do
    settings.update!(ai_config: settings.ai_config.deep_merge('agents' => { 'atendente_agendamento' => { 'no_card' => false } }))
    talk(last: :incoming, minutes_ago: 10)

    expect { described_class.perform_now }.not_to rescued
  end
end
