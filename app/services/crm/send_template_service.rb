# Envia uma mensagem modelo do WhatsApp para um contato, criando a conversa
# e a mensagem no histórico (status de entrega chega via webhook do Meta).
# `source` precisa responder a: account, inbox, sender, template_params,
# message_preview — Crm::Campaign e Crm::MessageAutomation servem.
class Crm::SendTemplateService
  pattr_initialize [:source!, :contact!]

  # retorna a conversation em caso de sucesso, nil se pulado
  def perform
    return nil if contact.phone_number.blank?

    processed = Whatsapp::LiquidTemplateProcessorService
                .new(campaign: source, contact: contact)
                .process_template_params(source.template_params)
    return nil if processed.nil?

    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: source.inbox).perform
    return nil if contact_inbox.blank?

    conversation = find_or_create_conversation(contact_inbox)

    conversation.messages.create!(
      account_id: source.account_id,
      inbox_id: source.inbox_id,
      message_type: :outgoing,
      content: render_content(processed),
      sender: source.sender,
      additional_attributes: { template_params: processed }
    )

    conversation
  end

  private

  def find_or_create_conversation(contact_inbox)
    existing = source.account.conversations
                     .where(inbox_id: source.inbox_id, contact_id: contact.id)
                     .order(created_at: :desc).first
    return existing if existing.present?

    ::Conversation.create!(
      account_id: source.account_id,
      inbox_id: source.inbox_id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def render_content(processed)
    body = source.message_preview.presence || source.name
    params = processed.dig('processed_params', 'body') || {}
    body.gsub(/\{\{\s*(\d+)\s*\}\}/) { params[Regexp.last_match(1)].to_s }
  end
end
