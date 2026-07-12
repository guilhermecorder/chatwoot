# Varre as mensagens das conversas de um contato procurando valores em R$
# (orçamentos passados no atendimento) e retorna o MAIOR encontrado.
#
# Formatos aceitos: "R$ 3.900", "R$ 3.900,00", "R$5.000", "R$ 11.900,00".
# Só considera valores prefixados por R$ para evitar falsos positivos
# (telefones, datas, números de protocolo).
class Crm::BudgetValueExtractor
  CURRENCY_REGEX = /R\$\s*(\d{1,3}(?:\.\d{3})*(?:,\d{2})?|\d+(?:,\d{2})?)/i
  # ignora valores irrisórios (ex.: "R$ 5" de taxa) e absurdos
  MIN_VALUE = 100
  MAX_VALUE = 500_000

  pattr_initialize [:account!, :contact!]

  # retorna o maior valor (Float) ou nil se nada encontrado
  def max_value
    values.max
  end

  def values
    conversation_ids = account.conversations.where(contact_id: contact.id).pluck(:id)
    return [] if conversation_ids.empty?

    contents = Message.where(conversation_id: conversation_ids)
                      .where.not(content: [nil, ''])
                      .pluck(:content)

    contents.flat_map { |text| parse_values(text) }
            .select { |v| v.between?(MIN_VALUE, MAX_VALUE) }
  end

  private

  def parse_values(text)
    text.scan(CURRENCY_REGEX).map do |match|
      raw = match.first
      # formato BR: ponto = milhar, vírgula = decimal
      normalized = raw.delete('.').tr(',', '.')
      Float(normalized)
    rescue ArgumentError
      nil
    end.compact
  end
end
