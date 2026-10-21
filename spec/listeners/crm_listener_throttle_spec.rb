require 'rails_helper'

# achado #194 da auditoria (07/10): o freio (throttle_minutes) do gatilho
# "Mensagem criada" só olhava o log de disparo — que nasce no FIM do job.
# Duas mensagens seguidas do paciente enfileiravam DOIS jobs da mesma
# automação antes de o primeiro terminar. Agora o listener também olha a
# marca "já enfileirado" no Redis.
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
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage) { pipeline.stages.create!(name: 'Novos Contatos', position: 0) }

  def automacao(throttle_minutes, delay_minutes: 0)
    Crm::Automation.create!(stage: stage, name: 'boas-vindas', trigger_type: 'message_created', action_type: 'send_template',
                            active: true, delay_minutes: delay_minutes,
                            action_config: { 'throttle_minutes' => throttle_minutes, 'inbox_id' => inbox.id,
                                             'template_params' => { 'name' => 'boas_vindas' } })
  end

  def chave(automation)
    "CRM_AUTOMATION_QUEUED::#{automation.id}::#{contact.id}"
  end

  def chega_mensagem(texto)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: texto)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  before { Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage) }

  after { Redis::LockManager.new.unlock(chave(automation)) if defined?(automation) }

  describe 'automação com freio de 10 minutos' do
    let!(:automation) { automacao(10) }

    it 'duas mensagens seguidas (antes de o job terminar) enfileiram UM job só (reprodução do achado)' do
      expect do
        chega_mensagem('oi')
        chega_mensagem('alô?')
      end.to have_enqueued_job(CrmAutomationFireJob).with(automation.id, contact.id, hash_including(event_type: 'message_created')).once
    end

    it 'grava a marca "já enfileirado" no Redis ao enfileirar' do
      chega_mensagem('oi')
      expect(Redis::LockManager.new.locked?(chave(automation))).to be(true)
    end

    it 'marca "já enfileirado" de outro processo segura o disparo mesmo sem log' do
      Redis::LockManager.new.lock(chave(automation), 60)
      expect { chega_mensagem('oi') }.not_to have_enqueued_job(CrmAutomationFireJob)
    end

    it 'log de disparo recente (dentro do freio) segura sem gravar a marca no Redis' do
      Crm::AutomationLog.create!(automation: automation, contact_id: contact.id, status: 'fired', payload: {}, fired_at: 2.minutes.ago)
      expect { chega_mensagem('oi') }.not_to have_enqueued_job(CrmAutomationFireJob)
      expect(Redis::LockManager.new.locked?(chave(automation))).to be(false)
    end

    it 'com a marca apagada (job terminou) e sem log de disparo, a próxima mensagem enfileira de novo' do
      chega_mensagem('oi')
      Redis::LockManager.new.unlock(chave(automation)) # o que o CrmAutomationFireJob faz ao terminar
      expect { chega_mensagem('alô?') }.to have_enqueued_job(CrmAutomationFireJob).once
    end

    it 'a marca dura o atraso + o freio (atraso de 5 min + freio de 10 min = 15 min)' do
      automation.update!(delay_minutes: 5)
      chega_mensagem('oi')
      expect(Redis::Alfred.ttl(chave(automation))).to be_between(14 * 60, 15 * 60)
    end
  end

  describe 'automação SEM freio' do
    let!(:automation) { automacao(0) }

    it 'cada mensagem dispara (ex.: fluxo n8n a cada mensagem) e nada é gravado no Redis' do
      expect do
        chega_mensagem('oi')
        chega_mensagem('alô?')
      end.to have_enqueued_job(CrmAutomationFireJob).twice
      expect(Redis::LockManager.new.locked?(chave(automation))).to be(false)
    end
  end
end
