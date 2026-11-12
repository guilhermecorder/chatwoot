# Custo do kit de cada tipo (string, micro): preço MÉDIO entre os fornecedores com cotação
# COMPLETA (kit + estrutura do telhado + frete). Regra do Guilherme, 11/11/2026.
# De cada fornecedor entra a opção completa mais barata daquele tipo; quem só tem cotação
# incompleta aparece na lista com o motivo, mas fica fora da média.
class Crm::KitQuote::Average
  TYPES = %w[string micro].freeze

  # { 'micro' => { 'cotacoes' => [...], 'fornecedores_na_media' => 1, 'media' => 7178.8 }, 'string' => {...} }
  def self.by_type(options)
    priced = options.select { |o| o['preco'].to_f.positive? }
    TYPES.index_with { |type| for_type(priced.select { |o| o['tipo'] == type }) }
  end

  def self.for_type(options)
    quotes = options.group_by { |o| o['fornecedor'] }.map { |_name, list| quote(list) }.sort_by { |q| q['valor'] }
    inside = quotes.select { |q| q['entra_na_media'] }
    {
      'cotacoes' => quotes,
      'fornecedores_na_media' => inside.size,
      'media' => inside.empty? ? nil : (inside.sum { |q| q['valor'] } / inside.size).round(2)
    }
  end

  # A cotação de um fornecedor: a completa mais barata; sem nenhuma completa, a mais barata (fora da média).
  def self.quote(list)
    pick = (list.select { |o| o['completa'] }.presence || list).min_by { |o| o['total'] }
    pick.slice('fornecedor', 'potencia_kwp', 'placas', 'paineis', 'inversor').merge(
      'valor' => pick['total'], 'entra_na_media' => pick['completa'], 'detalhe' => detail(pick)
    )
  end

  # "kit R$ 7.020,71 + frete R$ 158,09, com estrutura"  ·  "kit R$ 7.011,82, sem estrutura do telhado e frete"
  def self.detail(option)
    text = "kit #{Crm::KitQuote.money(option['preco'])}"
    text += " + frete #{Crm::KitQuote.money(option['frete'])}" if option['frete']
    option['completa'] ? "#{text}, com estrutura" : "#{text}, sem #{option['falta']}"
  end
end
