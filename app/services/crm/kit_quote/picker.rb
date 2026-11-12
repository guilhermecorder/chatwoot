# Escolhe até `max` opções POR FORNECEDOR (12/11, pedido do Guilherme: "dos mais caros para os
# mais baratos, uns 15 pra cada"), sem repetir o mesmo kit, garantindo a mais barata de cada
# (fornecedor, tipo) que respondeu, que é a que o gerador já deixa escolhida.
# A lista volta da mais cara para a mais barata.
class Crm::KitQuote::Picker
  IDENTITY = %w[fornecedor tipo paineis inversor potencia_kwp preco].freeze
  GUARANTEED_TYPES = %w[string micro].freeze

  def self.pick(options, max)
    unique_by_value(options).group_by { |o| o['fornecedor'] }.values.flat_map do |list|
      cheapest = guaranteed(list)
      by_price = list.sort_by { |o| -price(o) }
      (cheapest + by_price.reject { |o| cheapest.include?(o) }.first([max - cheapest.size, 0].max))
    end.sort_by { |o| -price(o) }
  end

  def self.price(option)
    (option['total'] || option['preco']).to_f
  end

  def self.unique_by_value(options)
    options.select { |o| o['preco'].to_f.positive? }
           .sort_by { |o| [o['preco_por_kwp'] || Float::INFINITY, o['preco']] }
           .uniq { |o| o.values_at(*IDENTITY) }
  end

  # A mais barata de cada (fornecedor, tipo). `unique` já vem da mais barata à mais cara.
  def self.guaranteed(unique)
    unique.select { |o| GUARANTEED_TYPES.include?(o['tipo']) }
          .group_by { |o| o.values_at('fornecedor', 'tipo') }
          .values.map(&:first)
  end
end
