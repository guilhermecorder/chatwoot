# 🗣️ O QUE O CLIENTE DISSE (15/11/2026, Guilherme: "quem monta o orçamento tem que ver com destaque, alto contraste, o
# que foi pego na conversa — ex.: o cliente disse que vai pôr 2 ar-condicionados — para estimar certo").
#
# Junta, para a caixa em destaque do Gerador:
#   ficha   → a ficha do cliente que o atendente preencheu (Crm::ClientSummary): conta, vai aumentar, telhado…
#   aumento → o "vai aumentar" lido pela tabela aprovada (Crm::KitQuote::Increase): itens com kWh + o que ela não cobre
#   frases  → as frases do PRÓPRIO cliente na conversa que falam de consumo (ar, piscina, chuveiro, carro elétrico,
#             aumentar a conta…), da mais nova para a mais antiga — para conferir o que a ficha pode ter deixado passar
#
#   Crm::KitQuote::ConversationFacts.new(contact).call
class Crm::KitQuote::ConversationFacts
  MAX_PHRASES = 6
  SCAN = 300 # últimas mensagens do cliente lidas
  MAX_TEXT = 220
  # o que importa para o tamanho do sistema (sem acento, minúsculo)
  TOPICS = /ar[- ]?condicionad|\bares\b|\bsplits?\b|\bbtus?\b|piscina|chuveiro|carro eletric|veiculo eletric|carregador|
            aquecedor|aquecimento|freezer|geladeira|hidro|banheira|forno eletric|sauna|aumentar|aumento|vai subir|
            mais placas|\bkwh\b|reforma|ampliac|casa nova|mudar de casa|sombra|edicula|outra casa/x

  def initialize(contact)
    @contact = contact
  end

  def call
    {
      'ficha' => ficha,
      'aumento' => increase,
      'frases' => phrases
    }
  end

  private

  # o orçamento já gerado e o CPF não ajudam a estimar: ficam fora da caixa
  HIDDEN_FIELDS = %w[orcamento cpf].freeze

  def ficha
    Crm::ClientSummary.for(@contact)[:fields]
                      .select { |row| row[:value] && HIDDEN_FIELDS.exclude?(row[:key]) }
                      .map { |row| { 'chave' => row[:key], 'rotulo' => row[:label], 'valor' => row[:value] } }
  rescue StandardError
    []
  end

  def increase
    text = Crm::KitQuote::ClientData.new(@contact).call['aumento']
    return nil if text.blank?

    Crm::KitQuote::Increase.parse(text).transform_keys(&:to_s).merge('texto' => text)
  end

  def phrases
    Message.where(account_id: @contact.account_id, conversation_id: @contact.conversations.select(:id))
           .where(message_type: :incoming, private: false).where.not(content: [nil, ''])
           .order(id: :desc).limit(SCAN)
           .select { |m| I18n.transliterate(m.content.to_s).downcase.match?(TOPICS) }
           .first(MAX_PHRASES)
           .map { |m| { 'texto' => m.content.to_s.squish.truncate(MAX_TEXT), 'em' => m.created_at.iso8601 } }
  end
end
