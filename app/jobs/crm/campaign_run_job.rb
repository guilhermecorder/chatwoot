class Crm::CampaignRunJob < ApplicationJob
  queue_as :low

  # Meta aceita bem mais, mas 5 msg/s evita bloqueio por qualidade
  THROTTLE_SECONDS = 0.2

  def perform(campaign_id)
    campaign = Crm::Campaign.find_by(id: campaign_id)
    return if campaign.blank? || !campaign.processing?

    contacts = campaign.resolve_audience
    stats = { 'total' => contacts.size, 'sent' => 0, 'skipped' => 0, 'failed' => 0 }
    campaign.update!(stats: stats, started_at: Time.current)

    contacts.find_each do |contact|
      process_contact(campaign, contact, stats)
      persist_progress(campaign, stats)
      sleep THROTTLE_SECONDS
    end

    campaign.update!(status: :completed, stats: stats, finished_at: Time.current)
  rescue StandardError => e
    Rails.logger.error "[Crm::CampaignRunJob] campaign #{campaign_id} failed: #{e.message}"
    campaign&.update(status: :failed, stats: (stats || {}).merge('error' => e.message), finished_at: Time.current)
  end

  private

  def process_contact(campaign, contact, stats)
    conversation = Crm::SendTemplateService.new(source: campaign, contact: contact).perform

    if conversation.nil?
      stats['skipped'] += 1
      return
    end

    record_recipient(campaign, contact, conversation)
    apply_label(campaign, contact)
    stats['sent'] += 1
  rescue StandardError => e
    Rails.logger.error "[Crm::CampaignRunJob] contact #{contact.id}: #{e.message}"
    stats['failed'] += 1
  end

  def record_recipient(campaign, contact, conversation)
    Crm::CampaignContact.create!(
      campaign: campaign,
      contact: contact,
      conversation: conversation,
      sent_at: Time.current
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil
  end

  def apply_label(campaign, contact)
    title = campaign.apply_label.to_s.strip.downcase
    return if title.blank?

    campaign.account.labels.find_or_create_by!(title: title)
    contact.label_list.add(title)
    contact.save!
  rescue StandardError => e
    Rails.logger.error "[Crm::CampaignRunJob] label '#{title}' contact #{contact.id}: #{e.message}"
  end

  def persist_progress(campaign, stats)
    processed_count = stats['sent'] + stats['skipped'] + stats['failed']
    campaign.update_column(:stats, stats) if (processed_count % 10).zero?
  end
end
