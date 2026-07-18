# Job que roda periodicamente (via Sidekiq Cron) para disparar automações
# do tipo card_stalled — quando um lead fica parado na coluna por muito tempo.
#
# Configurar no Sidekiq Cron (config/initializers/sidekiq.rb) para rodar a cada 30 min.
class CrmStalledCardsJob < ApplicationJob
  queue_as :default

  def perform
    Crm::Automation
      .where(active: true, trigger_type: 'card_stalled')
      .includes(stage: { pipeline: :account })
      .find_each do |automation|
        process_automation(automation)
      rescue StandardError => e
        # uma automação quebrada não pode derrubar a rodada inteira (todas as contas)
        Rails.logger.error "[CrmStalledCardsJob] automation #{automation.id}: #{e.message}"
      end
  end

  private

  def process_automation(automation)
    stall_threshold = automation.delay_minutes.to_i
    return if stall_threshold <= 0

    cutoff_time = stall_threshold.minutes.ago

    # Contacts that have been in this stage longer than the threshold
    stalled_contacts = Crm::Contact
      .where(stage: automation.stage)
      .where('stage_moved_at <= ?', cutoff_time)
      .includes(:contact)

    stalled_contacts.each do |crm_contact|
      fire_if_not_already_sent(automation, crm_contact)
    end
  end

  def fire_if_not_already_sent(automation, crm_contact)
    # Verifica se já disparou para este lead desde que ele entrou nesta etapa
    already_fired = Crm::AutomationLog
      .where(
        automation_id: automation.id,
        contact_id:    crm_contact.contact_id,
        status:        'fired'
      )
      .where('fired_at >= ?', crm_contact.stage_moved_at)
      .exists?

    return if already_fired

    # TRAVA SÍNCRONA: o log 'fired' é gravado pelo FireJob depois, em outra fila.
    # Sem isto, duas rodadas seguidas (cron 30 min) enfileiravam o disparo 2× para
    # o mesmo card antes do 1º log existir → mensagem/form duplicado. A chave inclui
    # stage_moved_at: se o card ENTRAR DE NOVO na coluna, pode disparar de novo.
    enqueue_key = "CRM_STALLED_ENQUEUED::#{automation.id}::#{crm_contact.contact_id}::#{crm_contact.stage_moved_at.to_i}"
    return unless Redis::LockManager.new.lock(enqueue_key, 6.hours)

    CrmAutomationFireJob.perform_later(
      automation.id,
      crm_contact.contact_id,
      {
        event_type:  'card_stalled',
        stage_id:    crm_contact.stage_id,
        stage_name:  crm_contact.stage.name,
        stalled_for: ((Time.current - crm_contact.stage_moved_at) / 60).round,
      }
    )
  end
end
