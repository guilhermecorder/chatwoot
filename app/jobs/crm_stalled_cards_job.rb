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
