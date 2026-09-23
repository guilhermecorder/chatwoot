require 'rails_helper'

# 📅 item 200: "Consulta confirmada: …" enviada pelo robô do N8N (ou pela
# equipe) → releitura do Secretário da Agenda em 15 s
RSpec.describe CrmListener do
  include ActiveJob::TestHelper

  around do |example|
    old = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = old
  end

  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def fire(message)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def outgoing(content, attrs = {})
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: content,
                     additional_attributes: attrs)
  end

  it '"Consulta confirmada:" do robô → agenda a releitura do Secretário com 15 s' do
    expect { fire(outgoing('Deu certo! Consulta confirmada: quarta-feira, 30/09 às 13:00. Nome: Ana')) }
      .to have_enqueued_job(Crm::SchedulerRecheckJob).with(conversation.id)
    expect(contact.reload.additional_attributes['cevico_anchor_read_at']).to be_present
  end

  it '"Prontinho, remarquei:" e "consulta cancelada" também disparam' do
    expect { fire(outgoing('Prontinho, remarquei: quinta, 01/10 às 08:30, Av. Paulista.')) }.to have_enqueued_job(Crm::SchedulerRecheckJob)
    contact.update!(additional_attributes: {})
    expect { fire(outgoing('Sua consulta cancelada, combinado.')) }.to have_enqueued_job(Crm::SchedulerRecheckJob)
  end

  it 'mensagem comum do robô não dispara' do
    expect { fire(outgoing('Tenho quarta 30/09 às 13:00 ou 14:15. Algum desses funciona?')) }
      .not_to have_enqueued_job(Crm::SchedulerRecheckJob)
  end

  it 'mensagem do Atendente interno (cevico_ia_agent) e da jornada ficam de fora' do
    expect { fire(outgoing('Deu certo! Consulta confirmada: quarta 30/09 às 13:00', { 'cevico_ia_agent' => 'atendente_agendamento' })) }
      .not_to have_enqueued_job(Crm::SchedulerRecheckJob)
    expect { fire(outgoing('Consulta confirmada para amanhã', { 'cevico_journey' => true })) }
      .not_to have_enqueued_job(Crm::SchedulerRecheckJob)
  end

  it 'freio: a confirmação picada em 2 balões só lê uma vez' do
    fire(outgoing('Deu certo! Consulta confirmada: quarta 30/09 às 13:00'))
    expect { fire(outgoing('Consulta confirmada, te esperamos!')) }.not_to have_enqueued_job(Crm::SchedulerRecheckJob)
  end

  it 'mensagem recebida (do paciente) com as mesmas palavras não é âncora' do
    incoming = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                content: 'minha consulta confirmada?')
    expect { fire(incoming) }.not_to have_enqueued_job(Crm::SchedulerRecheckJob)
  end
end
