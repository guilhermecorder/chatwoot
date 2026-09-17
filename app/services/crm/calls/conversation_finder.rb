# Acha (ou cria) o paciente e a conversa de uma ligação na caixa — mesmo
# padrão do Crm::SendTemplateService: contato pelo source_id da caixa, senão
# pelos últimos dígitos do telefone (Task.match_contact), senão novo;
# conversa = a última da caixa com esse contato (reaberta se resolvida) ou
# uma nova.
class Crm::Calls::ConversationFinder
  attr_reader :inbox, :wa_id, :name

  def initialize(inbox:, wa_id:, name: nil, contact: nil)
    @inbox = inbox
    @wa_id = wa_id.to_s.gsub(/\D/, '')
    @name = name
    @contact = contact
  end

  def account
    inbox.account
  end

  def contact
    @contact ||= inbox.contact_inboxes.find_by(source_id: wa_id)&.contact ||
                 Task.match_contact(account, wa_id) ||
                 create_contact
  end

  def contact_inbox
    @contact_inbox ||= ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: wa_id).perform
  end

  def conversation
    @conversation ||= existing_conversation || ::Conversation.create!(
      account_id: account.id, inbox_id: inbox.id, contact_id: contact.id, contact_inbox_id: contact_inbox.id
    )
  end

  private

  def existing_conversation
    existing = account.conversations.where(inbox_id: inbox.id, contact_id: contact.id).order(created_at: :desc).first
    return nil unless existing

    existing.update!(status: :open) if existing.resolved?
    existing
  end

  def create_contact
    account.contacts.create!(name: name.presence || "WhatsApp #{wa_id}", phone_number: "+#{wa_id}")
  rescue ActiveRecord::RecordInvalid
    # telefone já usado por outro cadastro que o casamento não achou (raro): não trava a ligação
    account.contacts.find_by(phone_number: "+#{wa_id}") || account.contacts.create!(name: name.presence || "WhatsApp #{wa_id}")
  end
end
