class Crm::MessageAutomationRunJob < ApplicationJob
  queue_as :low

  THROTTLE_SECONDS = 0.2

  def perform(automation_id)
    automation = Crm::MessageAutomation.find_by(id: automation_id)
    return if automation.blank? || !automation.active?

    stats = automation.stats.presence || {}
    stats['sent'] ||= 0
    stats['failed'] ||= 0

    automation.eligible_contacts.find_each do |contact|
      process_contact(automation, contact, stats)
      sleep THROTTLE_SECONDS
    end

    automation.update!(stats: stats.merge('last_run_at' => Time.current.iso8601))
  end

  private

  def process_contact(automation, contact, stats)
    conversation = Crm::SendTemplateService.new(source: automation, contact: contact).perform
    return if conversation.nil?

    # marca o contato para nunca receber esta régua de novo
    automation.account.labels.find_or_create_by!(title: automation.marker_label)
    contact.label_list.add(automation.marker_label)
    contact.save!

    stats['sent'] += 1
  rescue StandardError => e
    Rails.logger.error "[Crm::MessageAutomationRunJob] automation #{automation.id} contact #{contact.id}: #{e.message}"
    stats['failed'] += 1
  end
end
