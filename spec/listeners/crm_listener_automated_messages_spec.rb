require 'rails_helper'

# 21/09 (feedback da Vaneide): mensagem AUTOMÁTICA da clínica (lembrete de
# véspera, campanha…) não conta como "atendente respondeu" nas automações de
# coluna; e paciente que já tem consulta futura não nasce em "Novos Contatos"
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
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage_new) { pipeline.stages.create!(name: 'Novos Contatos', position: 0) }
  let!(:stage_budget) { pipeline.stages.create!(name: 'Envio de Orçamento', position: 1) }
  let!(:stage_booked) { pipeline.stages.create!(name: 'Agendamento de Consulta', position: 2) }

  def fire(message)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def outgoing(attrs = {})
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Lembrete: sua consulta é amanhã',
                     sender: admin, additional_attributes: attrs)
  end

  describe 'automação "mensagem enviada" em Novos Contatos → Envio de Orçamento' do
    let!(:automation) do
      Crm::Automation.create!(stage: stage_new, name: 'orçamento enviado', trigger_type: 'message_created', action_type: 'move_card', active: true,
                              action_config: { 'message_direction' => 'outgoing', 'target_stage_id' => stage_budget.id })
    end

    before { Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage_new) }

    it 'lembrete de véspera (mensagem automática) NÃO dispara' do
      expect { fire(outgoing('cevico_auto' => 'TemplateSource')) }.not_to have_enqueued_job(CrmAutomationFireJob)
    end

    it 'mensagem da jornada / robô de follow-up também não' do
      expect { fire(outgoing('cevico_followup_bot_id' => 3)) }.not_to have_enqueued_job(CrmAutomationFireJob)
    end

    it 'mensagem da atendente (humana) dispara' do
      expect { fire(outgoing) }.to have_enqueued_job(CrmAutomationFireJob)
    end

    it 'automação que PEDE mensagens automáticas dispara mesmo assim' do
      automation.update!(action_config: automation.action_config.merge('include_automated' => true))
      expect { fire(outgoing('cevico_auto' => 'Campaign')) }.to have_enqueued_job(CrmAutomationFireJob)
    end
  end

  describe 'conversa nova' do
    def created(conv)
      listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conv))
    end

    it 'paciente com consulta FUTURA nasce na coluna "ao agendar" do Atendente de Agendamento' do
      CrmSetting.create!(account: account, ai_config: { 'agents' => { 'atendente_agendamento' => { 'after_booking_stage_id' => stage_booked.id } } })
      account.tasks.create!(title: 'Consulta: Deusa', due_at: 1.day.from_now, task_type: 'consulta', contact: contact, creator: admin,
                            status: :todo, priority: :medium)
      created(conversation)
      expect(Crm::Contact.find_by(contact: contact, pipeline: pipeline).stage).to eq(stage_booked)
    end

    it 'sem consulta futura → primeira coluna' do
      created(conversation)
      expect(Crm::Contact.find_by(contact: contact, pipeline: pipeline).stage).to eq(stage_new)
    end
  end
end
