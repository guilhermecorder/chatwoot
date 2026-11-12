# Escolhe até `max` opções: as mais baratas por kWp, sem repetir o mesmo kit,
# garantindo a mais barata de cada (fornecedor, tipo) que respondeu.
class Crm::KitQuote::Picker
  IDENTITY = %w[fornecedor tipo paineis inversor potencia_kwp preco].freeze
  GUARANTEED_TYPES = %w[string micro].freeze

  def self.pick(options, max)
    unique = unique_by_value(options)
    chosen = guaranteed(unique)
    rest = unique.reject { |o| chosen.include?(o) }
    (chosen + rest).first(max).sort_by { |o| o['total'] || o['preco'] }
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
