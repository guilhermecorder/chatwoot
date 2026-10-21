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
    @conversation ||= existing_conversation || create_conversation
  end

  private

  # 📱 auditoria 10/2026 (#62): a conversa reaproveitada tem que ser a do
  # contact_inbox do número ATUAL (wa_id) — conversa presa a um contact_inbox
  # de número antigo mandaria a mensagem modelo para o telefone velho. Em caixa
  # que não amarra o source_id ao telefone, vale a mais recente, como sempre.
  def existing_conversation
    scope = account.conversations.where(inbox_id: inbox.id, contact_id: contact.id)
    existing = scope.where(contact_inbox_id: contact_inbox.id).order(created_at: :desc).first
    existing ||= scope.order(created_at: :desc).first unless Crm::SendTemplateService.phone_bound?(inbox)
    return nil unless existing

    existing.update!(status: :open) if existing.resolved?
    existing
  end

  # conversa nova no número atual; a presa ao número antigo (se houver) ganha a
  # nota de "telefone atualizado" — mesma decisão do Crm::SendTemplateService (#62)
  def create_conversation
    previous = nil
    if Crm::SendTemplateService.phone_bound?(inbox)
      previous = account.conversations.where(inbox_id: inbox.id, contact_id: contact.id)
                        .where.not(contact_inbox_id: contact_inbox.id).order(created_at: :desc).first
    end
    created = ::Conversation.create!(account_id: account.id, inbox_id: inbox.id, contact_id: contact.id, contact_inbox_id: contact_inbox.id)
    Crm::SendTemplateService.note_number_changed!(previous, created) if previous
    created
  end

  def create_contact
    account.contacts.create!(name: name.presence || "WhatsApp #{wa_id}", phone_number: "+#{wa_id}")
  rescue ActiveRecord::RecordInvalid
    # telefone já usado por outro cadastro que o casamento não achou (raro): não trava a ligação
    account.contacts.find_by(phone_number: "+#{wa_id}") || account.contacts.create!(name: name.presence || "WhatsApp #{wa_id}")
  end
end
