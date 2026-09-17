# Cria (ou atualiza) a mensagem-card da ligação na conversa: uma Message de
# atividade pública com content_attributes.cevico_call = to_payload. Toda
# mudança depois (gravação, transcrição) atualiza a MESMA mensagem — o
# update! já dispara o message.updated no cable e o card se redesenha.
class Crm::Calls::CardMessageBuilder
  attr_reader :call

  def initialize(call)
    @call = call
  end

  def perform
    conversation = call.conversation
    return nil unless conversation

    message = existing_message(conversation)
    return update_message(message) if message

    create_message(conversation)
  end

  private

  def existing_message(conversation)
    return nil if call.message_id.blank?

    conversation.messages.find_by(id: call.message_id)
  end

  def update_message(message)
    attrs = (message.content_attributes || {}).to_h.merge('cevico_call' => call.to_payload.deep_stringify_keys)
    message.update!(content: call.card_content, content_attributes: attrs)
    message
  end

  def create_message(conversation)
    message = conversation.messages.create!(
      account_id: call.account_id, inbox_id: call.inbox_id, message_type: :activity, private: false,
      content: call.card_content, content_attributes: { cevico_call: call.to_payload }
    )
    call.update_column(:message_id, message.id) # rubocop:disable Rails/SkipsModelValidations
    message
  end
end
