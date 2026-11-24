# 📨 CONTEÚDO GUARDADO ATÉ O "PODE MANDAR" (LIFE, 24/11/2026 · Guilherme): "todas as nossas mensagens modelo, ou elas
# são para pegar confirmação de sim e não, ou elas são apenas para reabrir conversa de janela de 24 horas… não dá para
# mandar orçamento por mensagem modelo".
#
# Quando a janela de 24 h está fechada, o que tem conteúdo (números da proposta, resumo em imagem) NÃO vai dentro da
# mensagem modelo: vai um abridor curto ("Posso te mandar?") e o conteúdo fica GUARDADO na conversa. Quando o cliente
# responde (a janela abriu), ele sai como mensagem normal, na hora.
#
#   Crm::PendingContent.store!(conversation, text: '…', image_blob_id: 12, origin: 'robo-7d')
#   Crm::PendingContent.handle_reply(message)
#     → :curto  respondeu só "Pode mandar"/"Sim"/"Quero" (o botão): o conteúdo saiu e o atendente IA NÃO responde junto
#     → :saiu   respondeu outra coisa (uma pergunta): o conteúdo saiu e o atendente IA responde a pergunta depois
#     → nil     nada guardado, guardado vencido (7 dias) ou "Agora não" (descarta e o atendente segue o AGORA NÃO)
class Crm::PendingContent
  KEY = 'cevico_conteudo_pendente'.freeze
  STAMP = 'cevico_conteudo_guardado'.freeze
  TTL = 7.days
  NO = /\A\W*(agora n[aã]o|n[aã]o|nao|pare|parar|sair|n[aã]o quero|sem interesse)\b/i
  SHORT_YES = /\A\W*(pode mandar|pode|manda|sim|quero|quero ver|quero saber|ok|okay|claro|pode sim|manda sim|bora|isso)\W*\z/i

  def self.store!(conversation, text:, origin:, image_blob_id: nil)
    return if conversation.nil? || text.blank?

    data = { 'texto' => text, 'imagem' => image_blob_id, 'origem' => origin, 'em' => Time.current.iso8601 }.compact
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge(KEY => data) }
  end

  def self.pending(conversation) # rubocop:disable Metrics/CyclomaticComplexity
    data = (conversation&.additional_attributes || {})[KEY]
    return nil unless data.is_a?(Hash) && data['texto'].present?

    at = Time.zone.parse(data['em'].to_s) rescue nil # rubocop:disable Style/RescueModifier
    at && at > TTL.ago ? data : nil
  end

  def self.clear!(conversation)
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.except(KEY) }
  end

  def self.handle_reply(message) # rubocop:disable Metrics/CyclomaticComplexity
    return nil unless message&.incoming?

    conversation = message.conversation
    data = pending(conversation)
    return nil if data.nil?

    clear!(conversation)
    return nil if message.content.to_s.match?(NO)

    deliver!(conversation, data)
    message.content.to_s.strip.match?(SHORT_YES) || message.content.to_s.strip.empty? ? :curto : :saiu
  rescue StandardError => e
    Rails.logger.error "[Crm::PendingContent] conversa #{message&.conversation_id}: #{e.class}: #{e.message}"
    nil
  end

  def self.deliver!(conversation, data)
    attrs = { STAMP => data['origem'].to_s }
    message = conversation.messages.new(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                        message_type: :outgoing, content: data['texto'], additional_attributes: attrs)
    blob = data['imagem'].presence && ActiveStorage::Blob.find_by(id: data['imagem'])
    message.attachments.new(account_id: conversation.account_id, file_type: :image, file: blob) if blob
    message.save!
  end
end
