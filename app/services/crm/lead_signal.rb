# 🚦 SINAL DE INTERESSE REAL (LIFE, 25/11/2026 · pedido do Guilherme: "a IA está pondo conversa simples ou até lixo
# como 'solicitou a conta'"). Caso real: conversa #144, a pessoa mandou só um link estranho e depois "Erro", e o
# atendente marcou em_atendimento → o cartão foi para "Solicitação da Conta".
#
# Regra: o cartão só anda quando o CLIENTE escreveu algo dele sobre o caso. NÃO contam:
#   · a mensagem pronta do anúncio ou da página do site (é o botão que ele clicou, não uma conversa);
#   · saudação, "ok", "obrigado", "sim", "não", "erro", "teste", emoji, pontuação;
#   · link solto; "This message is unavailable" (mensagem que o WhatsApp não entregou).
# Contam: qualquer frase com conteúdo ("casa", "qual o valor?", "minha conta vem 400") e áudio, foto, PDF ou vídeo.
# Para etapas da CONTA (conta_recebida / conta-recebida) é preciso mais: a conta anotada na ficha do cliente
# ou uma foto/PDF que ele mandou.
module Crm::LeadSignal
  NOISE_WORDS = %w[
    oi oii oie ola opa ei eai ai bom boa dia tarde noite tudo td bem tb tbm
    ok okay okk blz beleza certo certinho show top joia legal massa entendi
    obrigado obrigada obg obgd brigado valeu vlw grato grata
    sim nao n s claro pode
    erro error teste test hello hi
    tchau ate mais abraco falar fala agora diga manda aqui
    this message is unavailable
  ].to_set.freeze
  URL = %r{(?:https?://|www\.)\S+|\b[a-z0-9-]+\.(?:com|net|org|br|io|co|me|ly|xyz|site|online|info)(?:/\S*)?}i
  # frase pronta dos anúncios: a antiga ("Vi o anúncio da Life…") e a nova de 25/11 ("Quero um orçamento das placas solares")
  PREFILLED = /\bvi (?:o|a|seu|sua) (?:anuncio|pagina|propaganda|post|video)\b|\A(?:oi )?quero um orcamento das placas solares\z/
  MEDIA = %w[audio image file video].freeze
  BILL_STAGE = /conta/i

  module_function

  # a pessoa já disse algo dela sobre o caso?
  def interested?(conversation)
    real_messages(conversation).any?
  end

  # mensagens do cliente que contam como conversa de verdade
  def real_messages(conversation)
    return [] if conversation.nil?

    incoming = conversation.messages.where(message_type: :incoming, private: false).reorder(:created_at).includes(:attachments).to_a
    first_id = incoming.first&.id
    incoming.select do |msg|
      next true if media?(msg)
      next false if msg.id == first_id && prefilled?(conversation, msg.content)

      meaningful_text?(msg.content)
    end
  end

  # foto/PDF/áudio/vídeo do cliente
  def media?(msg)
    msg.attachments.any? { |a| MEDIA.include?(a.file_type.to_s) }
  end

  # 1ª mensagem que veio pronta do anúncio ou de uma página do site
  def prefilled?(conversation, text)
    plain = plain(text)
    return true if plain.match?(PREFILLED)

    attrs = conversation.additional_attributes || {}
    return true if attrs['meta_ads'].present? && attrs.dig('origem_whatsapp', 'tipo').to_s == 'anuncio'
    return true if attrs.dig('origem_whatsapp', 'tipo').to_s == 'site'

    Crm::WhatsappOrigin.match_page(conversation.account, text).present?
  rescue StandardError
    false
  end

  # sobra alguma palavra de verdade depois de tirar link, saudação e cortesia?
  def meaningful_text?(text)
    words = plain(text.to_s.gsub(URL, ' ')).split
    words.any? { |w| w.length >= 3 && NOISE_WORDS.exclude?(w) && w.match?(/[a-z]/) } ||
      words.any? { |w| w.match?(/\A\d{2,}\z/) } # um número solto ("400") é resposta
  end

  # a conta de luz chegou? (anotada na ficha OU foto/PDF do cliente)
  def bill_received?(conversation, contact)
    return true if bill_noted?(contact)
    return false if conversation.nil?

    conversation.messages.where(message_type: :incoming, private: false).joins(:attachments)
                .exists?(attachments: { file_type: %w[image file] })
  end

  def bill_noted?(contact)
    return false if contact.nil?

    entry = ((contact.additional_attributes || {})[Crm::ClientSummary::ATTR_KEY] || {})['conta']
    entry.is_a?(Hash) ? entry['valor'].to_s.strip.present? : entry.to_s.strip.present?
  end

  # nil = pode marcar; texto = por que não (vai para a IA)
  def stage_problem(etapa, conversation, contact)
    unless interested?(conversation)
      return 'Ainda não: o cliente só mandou a mensagem pronta do anúncio/página, saudação, link, "erro" ou emoji. ' \
             'Marque etapa só depois que ele contar algo do caso dele (onde quer instalar, quanto vem a conta, ' \
             'pediu orçamento ou perguntou preço). Continue a conversa normalmente.'
    end
    return nil unless etapa.to_s.match?(BILL_STAGE)
    return nil if bill_received?(conversation, contact)

    'Ainda não: a conta de luz não chegou. Esta etapa é só quando ele mandar o valor da conta (anote com ' \
      'anotar_cliente, campo conta) ou a foto/PDF da conta.'
  end

  def plain(text)
    I18n.transliterate(text.to_s.downcase, replacement: '').gsub(/[^a-z0-9 ]+/, ' ').squeeze(' ').strip
  end
end
