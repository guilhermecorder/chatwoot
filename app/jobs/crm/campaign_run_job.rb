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
    processed = Whatsapp::LiquidTemplateProcessorService
                .new(campaign: campaign, contact: contact)
                .process_template_params(campaign.template_params)

    if processed.nil?
      stats['skipped'] += 1
      return
    end

    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: campaign.inbox).perform
    if contact_inbox.blank?
      stats['skipped'] += 1
      return
    end

    conversation = find_or_create_conversation(campaign, contact, contact_inbox)

    conversation.messages.create!(
      account_id: campaign.account_id,
      inbox_id: campaign.inbox_id,
      message_type: :outgoing,
      content: render_content(campaign, processed),
      sender: campaign.sender,
      additional_attributes: { template_params: processed, crm_campaign_id: campaign.id }
    )

    apply_label(campaign, contact)
    stats['sent'] += 1
  rescue StandardError => e
    Rails.logger.error "[Crm::CampaignRunJob] contact #{contact.id}: #{e.message}"
    stats['failed'] += 1
  end

  def find_or_create_conversation(campaign, contact, contact_inbox)
    existing = campaign.account.conversations
                       .where(inbox_id: campaign.inbox_id, contact_id: contact.id)
                       .order(created_at: :desc).first
    return existing if existing.present?

    ::Conversation.create!(
      account_id: campaign.account_id,
      inbox_id: campaign.inbox_id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    )
  end

  # Substitui {{1}}, {{2}}… do corpo do template pelos parâmetros já
  # renderizados, para a mensagem aparecer legível no histórico da conversa
  def render_content(campaign, processed)
    body = campaign.message_preview.presence || campaign.name
    params = processed.dig('processed_params', 'body') || {}
    body.gsub(/\{\{\s*(\d+)\s*\}\}/) { params[Regexp.last_match(1)].to_s }
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
