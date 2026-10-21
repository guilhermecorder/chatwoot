require 'rails_helper'

# 🏥 item 300 (30/09): origem CEVICO × Oftalmofácil escolhida na Agenda +
# "confirmou" ⇄ coluna "Consulta Confirmada" no funil certo.
RSpec.describe 'Origem do agendamento e confirmação (item 300)' do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around do |example|
    old = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = old
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let!(:own) { Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0) }
  let!(:booked) { own.stages.create!(name: 'Agendamento de Consulta', position: 2) }
  let!(:confirmed) { own.stages.create!(name: 'Consulta Confirmada', position: 3) }
  let!(:missed) { own.stages.create!(name: 'Não Foi a Consulta', position: 4) }
  let!(:done) { own.stages.create!(name: 'Consulta Realizada', position: 5) }
  let!(:partner) { Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1) }
  let!(:partner_surgery) { partner.stages.create!(name: 'Cirurgia Agendada', position: 0) }

  before do
    CrmSetting.create!(account: account, agenda_config: {
                         'oftalmofacil' => { 'partner_pipeline_id' => partner.id },
                         'booking' => { 'stage_id' => booked.id },
                         'attendance_stages' => { 'missed_stage_id' => missed.id }
                       })
  end

  def book(origin:, phone: '(11) 98888-7777', name: 'Joãozinho', contact: nil)
    task = account.tasks.create!(title: name, phone: phone, task_type: 'consulta', creator: admin, assignee: admin,
                                 origin: origin, contact: contact, unit: 'tatuape', due_at: tz.now.tomorrow.change(hour: 9))
    Crm::AppointmentOrigin.apply(account: account, task: task)
    task.reload
  end

  describe Crm::AppointmentOrigin do
    it 'Oftalmofácil: cria o contato, etiqueta of_agenda e card em "Consulta Agendada" do funil do Oftalmofácil' do
      task = book(origin: 'oftalmofacil')
      contact = task.contact
      expect(contact.phone_number).to eq('+5511988887777')
      expect(contact.label_list).to include('oftalmofacil', 'of_agenda')
      card = Crm::Contact.find_by(contact_id: contact.id)
      expect(card.pipeline_id).to eq(partner.id)
      expect(card.stage.name).to eq('Consulta Agendada')
      expect(partner.stages.order(:position).pluck(:name)).to eq(['Consulta Agendada', 'Cirurgia Agendada'])
      expect(Crm::PartnerGuard.partner_task?(task)).to be(true)
      expect(Crm::PartnerGuard.partner_contact?(contact)).to be(true)
      expect(enqueued_jobs.select { |j| j['job_class'] == 'CrmAutomationFireJob' }).to be_empty
    end

    it 'CEVICO: cria o contato, etiqueta cevico e card na coluna de agendamento da CEVICO' do
      task = book(origin: 'cevico')
      expect(task.contact.label_list).to include('cevico')
      expect(task.contact.label_list).not_to include('of_agenda')
      card = Crm::Contact.find_by(contact_id: task.contact_id)
      expect([card.pipeline_id, card.stage_id]).to eq([own.id, booked.id])
      expect(Crm::PartnerGuard.partner_task?(task)).to be(false)
    end

    it 'CEVICO: quem já tem card fica onde está' do
      contact = create(:contact, account: account, phone_number: '+5511988887777')
      Crm::Contact.create!(contact_id: contact.id, pipeline_id: own.id, stage_id: done.id)
      book(origin: 'cevico')
      expect(Crm::Contact.find_by(contact_id: contact.id, pipeline_id: own.id).stage_id).to eq(done.id)
    end

    it 'sem telefone válido não cria contato (a origem fica no agendamento)' do
      task = book(origin: 'oftalmofacil', phone: '')
      expect(task.contact_id).to be_nil
      expect(task.origin).to eq('oftalmofacil')
      expect(Crm::PartnerGuard.partner_task?(task)).to be(true)
    end

    it 'trocar de Oftalmofácil para CEVICO tira a of_agenda' do
      task = book(origin: 'oftalmofacil')
      task.update!(origin: 'cevico')
      described_class.apply(account: account, task: task)
      expect(task.contact.reload.label_list).to include('cevico')
      expect(task.contact.label_list).not_to include('of_agenda')
    end
  end

  describe Crm::ConfirmationReflector do
    it 'paciente da CEVICO confirmou → card anda para "Consulta Confirmada" e dispara as automações da coluna' do
      Crm::Automation.create!(stage: confirmed, name: 'aviso', trigger_type: 'card_entered',
                              action_type: 'webhook', action_config: { 'url' => 'https://example.com' }, active: true)
      task = book(origin: 'cevico')
      expect(described_class.call(account: account, task: task)).to eq('Consulta Confirmada')
      expect(Crm::Contact.find_by(contact_id: task.contact_id, pipeline_id: own.id).stage_id).to eq(confirmed.id)
      expect(enqueued_jobs.count { |j| j['job_class'] == 'CrmAutomationFireJob' }).to eq(1)
    end

    it 'paciente do Oftalmofácil confirmou → "Consulta Confirmada" do funil DELE, sem card na CEVICO e sem automação' do
      task = book(origin: 'oftalmofacil')
      expect(described_class.call(account: account, task: task)).to eq('Consulta Confirmada')
      cards = Crm::Contact.where(contact_id: task.contact_id)
      expect(cards.pluck(:pipeline_id)).to eq([partner.id])
      expect(cards.first.stage.name).to eq('Consulta Confirmada')
      expect(partner.stages.order(:position).pluck(:name)).to eq(['Consulta Agendada', 'Consulta Confirmada', 'Cirurgia Agendada'])
      expect(enqueued_jobs.select { |j| j['job_class'] == 'CrmAutomationFireJob' }).to be_empty
    end

    it 'card que já passou da confirmação não volta; quem faltou e remarcou volta a confirmar' do
      task = book(origin: 'cevico')
      card = Crm::Contact.find_by(contact_id: task.contact_id, pipeline_id: own.id)
      card.update!(stage_id: done.id)
      expect(described_class.call(account: account, task: task)).to be_nil
      expect(card.reload.stage_id).to eq(done.id)
      card.update!(stage_id: missed.id)
      expect(described_class.call(account: account, task: task)).to eq('Consulta Confirmada')
    end

    it 'card ENTROU na coluna "Consulta Confirmada" (equipe/N8N) → a próxima consulta fica confirmada' do
      task = book(origin: 'cevico')
      expect(task.confirmed_at).to be_nil
      Crm::Contact.find_by(contact_id: task.contact_id, pipeline_id: own.id).update!(stage_id: confirmed.id)
      expect(task.reload.confirmed_at).to be_present
    end

    it 'entrar em outra coluna não confirma nada' do
      task = book(origin: 'cevico')
      Crm::Contact.find_by(contact_id: task.contact_id, pipeline_id: own.id).update!(stage_id: done.id)
      expect(task.reload.confirmed_at).to be_nil
    end
  end

  describe 'SIM ao lembrete (CrmListener)' do
    let(:inbox) { create(:inbox, account: account, name: 'OFTALMOFÁCIL') }

    it 'paciente do Oftalmofácil: confirma a consulta e o card vai para o funil do Oftalmofácil' do
      task = book(origin: 'oftalmofacil')
      contact = task.contact
      contact.update!(additional_attributes: contact.additional_attributes.merge(
        'cevico_appt_reminders' => { task.id.to_s => { 'd1' => Time.current.iso8601 } }
      ))
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'SIM')
      CrmListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message))

      expect(task.reload.confirmed_at).to be_present
      cards = Crm::Contact.where(contact_id: contact.id)
      expect(cards.pluck(:pipeline_id)).to eq([partner.id])
      expect(cards.first.stage.name).to eq('Consulta Confirmada')
      expect(conversation.messages.where(private: true).last.content).to include('Card → Consulta Confirmada')
    end
  end
end
