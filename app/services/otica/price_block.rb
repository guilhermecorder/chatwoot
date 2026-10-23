# 👓 A tabela de preços do AGENTE lida dos produtos da ótica. Quando a conta é
# do ramo ótica e tem produto ativo com preço, o roteiro recebe faixas por
# tipo e grife ("Armações Ray-Ban: de R$ 450 a R$ 980, 12 modelos") e as
# lentes uma a uma — em vez de valores digitados à mão na Tabela de preços.
# Sem produto (ou ramo clínica) não muda nada: Cevico::PriceList segue igual.
class Otica::PriceBlock
  MAX_LENS_LINES = 25
  MAX_BRAND_LINES = 20

  def self.applies?(account)
    return false if account.nil?
    return false unless Cevico::Company.for(account).segment == 'otica'

    Otica::Product.where(account_id: account.id).active.priced.exists?
  rescue StandardError
    false
  end

  def self.prompt_block(account) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    products = Otica::Product.where(account_id: account.id).active.priced.to_a
    lines = []

    %w[armacao solar].each do |kind|
      rows = products.select { |p| p.kind == kind }
      next if rows.empty?

      by_brand = rows.group_by { |p| p.brand.presence || 'Sem grife' }.sort_by { |_b, list| -list.size }.first(MAX_BRAND_LINES)
      parts = by_brand.map do |brand, list|
        prices = list.map(&:price)
        range = prices.min == prices.max ? "R$ #{money(prices.min)}" : "de R$ #{money(prices.min)} a R$ #{money(prices.max)}"
        "#{brand} #{range} (#{list.size} #{list.size == 1 ? 'modelo' : 'modelos'})"
      end
      lines << "- #{Otica::Product::KINDS[kind]}: #{parts.join(' · ')}."
    end

    %w[lente lente_contato servico outro].each do |kind|
      rows = products.select { |p| p.kind == kind }.sort_by(&:price).first(MAX_LENS_LINES)
      next if rows.empty?

      parts = rows.map do |p|
        label = [p.name, p.lens_type.present? ? Otica::Product::LENS_TYPES[p.lens_type]&.downcase : nil].compact.join(', ')
        text = "#{label} R$ #{money(p.price)}"
        text += " (promoção; preço normal R$ #{money(p.list_price)})" if p.promo_active?
        text += " — prazo do laboratório #{p.lab_days} dias" if p.lab_days.positive? && kind == 'lente'
        text
      end
      lines << "- #{Otica::Product::KINDS[kind]}: #{parts.join(' · ')}."
    end

    lines << '- Os valores são da tabela da loja hoje; o orçamento final depende da receita (grau) e da lente escolhida. ' \
             'Armação e lentes são vendidas separadas; o preço do óculos completo é a soma.'
    lines.join("\n")
  end

  def self.money(value)
    number = value.to_f
    whole = number.floor
    text = whole.to_s.gsub(/(\d)(?=(\d{3})+$)/, '\\1.')
    cents = ((number - whole) * 100).round
    cents.zero? ? text : "#{text},#{format('%02d', cents)}"
  end
end
