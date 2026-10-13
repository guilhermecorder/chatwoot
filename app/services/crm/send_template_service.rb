# Envia uma mensagem modelo do WhatsApp para um contato, criando a conversa
# e a mensagem no histórico (status de entrega chega via webhook do Meta).
# `source` precisa responder a: account, inbox, sender, template_params,
# message_preview — Crm::Campaign e Crm::MessageAutomation servem.
class Crm::SendTemplateService
  pattr_initialize [:source!, :contact!]

  # 🚫 auditoria 10/2026 (#45): a Meta recusa a mensagem modelo DEPOIS que ela
  # foi gravada (o envio é assíncrono): a mensagem fica status 'failed' com o
  # erro em external_error. Quem chama guarda `message.id` e, na rodada
  # seguinte do seu cron, confere `Crm::SendTemplateService.refused(ids)` para
  # devolver a marca e listar como "a Meta recusou". O retorno de `perform`
  # continua sendo a conversa (ou nil).
  attr_reader :message

  # { message_id => texto do erro da Meta } das mensagens que a Meta recusou
  def self.refused(message_ids)
    ids = Array(message_ids).compact
    return {} if ids.empty?

    Message.where(id: ids, status: :failed).to_h { |m| [m.id, refusal_text(m)] }
  end

  def self.refusal_text(message)
    message.external_error.to_s.strip.presence || 'a Meta recusou o envio'
  end

  # caixa em que o source_id do contact_inbox É o telefone (WhatsApp, SMS,
  # Twilio): conversa de outro contact_inbox é de outro número
  def self.phone_bound?(inbox)
    inbox.present? && (inbox.whatsapp? || inbox.sms? || inbox.twilio?)
  end

  # nota (privada) na conversa presa ao número antigo: a equipe entende por
  # que as mensagens passaram a sair em outra conversa (#62)
  def self.note_number_changed!(old_conversation, new_conversation)
    old_tail = old_conversation.contact_inbox&.source_id.to_s.last(4)
    new_tail = new_conversation.contact_inbox&.source_id.to_s.last(4)
    old_conversation.messages.create!(
      account_id: old_conversation.account_id, inbox_id: old_conversation.inbox_id, message_type: :activity, private: true,
      content: "📱 Telefone atualizado na ficha (…#{old_tail} → …#{new_tail}): as mensagens seguem na conversa " \
               "##{new_conversation.display_id}. Esta conversa era do número antigo."
    )
  rescue StandardError => e
    Rails.logger.warn "[CEVICO mensagem modelo] nota do número novo (conversa #{old_conversation.id}): #{e.message}"
  end

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
    @message = create_message(conversation, processed)
    conversation
  end

  private

  def create_message(conversation, processed)
    conversation.messages.create!(
      account_id: source.account_id,
      inbox_id: source.inbox_id,
      message_type: :outgoing,
      content: render_content(processed),
      sender: source.sender,
      # 'cevico_auto' (21/09, feedback da Vaneide): esta mensagem saiu de um
      # robô (lembrete, régua, campanha…), não de um atendente — as automações
      # de coluna "mensagem enviada" ignoram mensagens automáticas
      additional_attributes: { template_params: processed, 'cevico_auto' => auto_label }
    )
  end

  def auto_label
    source.respond_to?(:auto_label) ? source.auto_label.to_s : source.class.name.demodulize
  end

  # 📱 auditoria 10/2026 (#62): o envio real usa o número do contact_inbox DA
  # CONVERSA (conversation.contact_inbox.source_id). Quando a equipe corrige o
  # telefone na ficha, a conversa antiga continua presa ao número velho — por
  # isso a conversa reaproveitada tem que ser a do contact_inbox do telefone
  # ATUAL. Sem conversa nele, nasce uma nova (o histórico antigo fica na
  # conversa velha: era outro número). Em caixa que não amarra o source_id ao
  # telefone (API, site), vale a conversa mais recente, como sempre.
  #
  # DECISÃO (revisão da Rodada 3; o Guilherme confirma): a conversa velha NÃO
  # é re-apontada para o número novo nem fechada sozinha — se o número antigo
  # era de um terceiro, o histórico dele não pode virar a conversa da
  # paciente, e fechar uma conversa que a equipe talvez esteja usando seria
  # surpresa. Ela só ganha uma nota de atividade dizendo que o telefone mudou
  # e em qual conversa as mensagens seguem. A alternativa (um fio só,
  # re-apontando contact_inbox_id) fica registrada no BACKLOG.
  def find_or_create_conversation(contact_inbox)
    existing_conversation(contact_inbox) || create_conversation(contact_inbox)
  end

  def create_conversation(contact_inbox)
    previous = latest_in_other_number(contact_inbox)
    conversation = ::Conversation.create!(
      account_id: source.account_id,
      inbox_id: source.inbox_id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    )
    self.class.note_number_changed!(previous, conversation) if previous
    conversation
  end

  # a conversa mais recente do paciente nesta caixa, presa a OUTRO número
  def latest_in_other_number(contact_inbox)
    return nil unless self.class.phone_bound?(source.inbox)

    source.account.conversations.where(inbox_id: source.inbox_id, contact_id: contact.id)
          .where.not(contact_inbox_id: contact_inbox.id).order(created_at: :desc).first
  end

  def existing_conversation(contact_inbox)
    scope = source.account.conversations.where(inbox_id: source.inbox_id, contact_id: contact.id)
    existing = scope.where(contact_inbox_id: contact_inbox.id).order(created_at: :desc).first
    return existing if existing || self.class.phone_bound?(source.inbox)

    scope.order(created_at: :desc).first
  end

  def render_content(processed)
    body = source.message_preview.presence || source.name
    params = processed.dig('processed_params', 'body') || {}
    body.gsub(/\{\{\s*(\d+)\s*\}\}/) { params[Regexp.last_match(1)].to_s }
  end
end
