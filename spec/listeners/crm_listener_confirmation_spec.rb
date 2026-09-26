require 'rails_helper'

# 📅 item 217 (23/09): SIM/NÃO ao lembrete da véspera ficam NA CONSULTA
# (confirmed_at / declined_at); NÃO nunca cancela sozinho; na caixa do
# lembrete, "consulta confirmada" da equipe não vira consulta nova.
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
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, name: 'CONFIRMAÇÃO DE CONSULTA') }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let!(:task) do
    account.tasks.create!(title: 'Consulta: Ana', task_type: 'consulta', creator: admin, assignee: admin, contact: contact,
                          unit: 'tatuape', due_at: tz.now.tomorrow.change(hour: 11))
  end

  before do
    contact.update!(additional_attributes: { 'cevico_appt_reminders' => { task.id.to_s => { 'd1' => Time.current.iso8601 } } })
  end

  def fire(message)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def incoming(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  it 'SIM ao lembrete → confirmed_at na consulta + nota' do
    fire(incoming('SIM'))
    expect(task.reload.confirmed_at).to be_present
    expect(task.declined_at).to be_nil
    expect(conversation.messages.where(private: true).last.content).to include('CONFIRMOU')
  end

  it 'NÃO ao lembrete → declined_at, etiqueta confirmar_urgente, nota e aviso; a consulta NÃO é cancelada' do
    fire(incoming('NÃO'))
    task.reload
    expect(task.declined_at).to be_present
    expect(task.canceled_at).to be_nil
    expect(contact.reload.label_list).to include('confirmar_urgente')
    expect(conversation.reload.label_list).to include('confirmar_urgente')
    expect(conversation.messages.where(private: true).last.content).to include('respondeu NÃO')
    alerts = CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts')
    expect(alerts.last).to include('kind' => 'nao_confirmou', 'task_id' => task.id, 'user_id' => admin.id)
  end

  it '"não vou poder" também conta como NÃO; um SIM depois desfaz o NÃO' do
    fire(incoming('não vou poder ir'))
    expect(task.reload.declined_at).to be_present
    fire(incoming('sim, confirmo'))
    expect(task.reload.confirmed_at).to be_present
    expect(task.declined_at).to be_nil
  end

  it 'na caixa do lembrete, "consulta confirmada" enviada pela equipe NÃO dispara o Secretário; "remarquei" dispara' do
    CrmSetting.find_or_create_by!(account: account).update!(agenda_config: { 'appointment_reminders' => { 'd1' => { 'inbox_id' => inbox.id } } })
    human = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                             content: 'Consulta confirmada para amanhã às 11h, até lá!')
    expect { fire(human) }.not_to have_enqueued_job(Crm::SchedulerRecheckJob)
    contact.update!(additional_attributes: contact.additional_attributes.merge('cevico_anchor_read_at' => nil))
    moved = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                             content: 'Prontinho, remarquei: quinta 10h.')
    expect { fire(moved) }.to have_enqueued_job(Crm::SchedulerRecheckJob)
  end

  it 'paciente do Oftalmofácil: SIM ao lembrete confirma a consulta, mas nenhum agente é chamado', :aggregate_failures do
    contact.update!(additional_attributes: contact.additional_attributes.merge('parceiro' => 'CLINICA X'))
    expect(listener).not_to receive(:handle_responder_agents)
    fire(incoming('sim'))
    expect(task.reload.confirmed_at).to be_present
  end
end
