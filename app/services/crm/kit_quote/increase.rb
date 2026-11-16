# 🔌 AUMENTO DE CONSUMO previsto → kWh a somar no orçamento automático (tabela aprovada pelo Guilherme em 13/11/2026,
# depois de cruzar a pesquisa no Google com a do Gemini; média do mês ao longo do ano, uso real em Piracicaba).
#   Crm::KitQuote::Increase.parse('vai pôr 2 ar-condicionados de 12 mil e um carro elétrico')
#     → { itens: [{ 'rotulo' => '2 ar-condicionados (12.000 BTU)', 'kwh' => 180 }, { 'rotulo' => 'carro elétrico', 'kwh' => 200 }],
#         desconhecido: nil }
#   desconhecido = o trecho que a tabela não cobre (ex.: aquecedor de piscina de resistência, sauna): o orçamento fica
#   com o Fernando.
class Crm::KitQuote::Increase
  AR_BY_BTU = [[9_000, 70], [12_000, 90], [18_000, 120], [Float::INFINITY, 150]].freeze
  AIR_KEYS = { 70 => 'ar_9', 90 => 'ar_12', 120 => 'ar_18', 150 => 'ar_24' }.freeze # kWh por aparelho → botão do Gerador
  AR_UNKNOWN = 90 # sem o tamanho: o de 12 mil, o mais comum
  CAR = 200 # 1.200 km/mês × 15 kWh/100 km × 1,15 de perda na recarga
  CAR_PER_KM = 0.15 * 1.15
  POOL_FILTER = 100
  POOL_HEAT_PUMP = 400 # aquecimento 300 + filtro 100
  SHOWER = 70
  FRIDGE = 60
  HOT_TUB = 35
  OVEN = 30
  AIR = /ar[- ]?condicionad|\bar(es)?\b|\bsplits?\b/
  ROOMS = /em (\d+|dois|duas|tres|quatro|cinco|seis) (quartos|comodos|ambientes|salas|suites)/
  NUMBERS = { 'um' => 1, 'uma' => 1, 'dois' => 2, 'duas' => 2, 'tres' => 3, 'quatro' => 4, 'cinco' => 5, 'seis' => 6 }.freeze
  QTY = /(\d+|um|uma|dois|duas|tres|quatro|cinco|seis)\s+(?:\S+\s+){0,2}?/
  # trecho só de quando/como ("começo do ano", "em breve") não é aparelho
  TIME_WORDS = %w[no na em para pro pra ate daqui la logo depois quando proxim comeco inicio fim final breve ano mes meses semana verao
                  inverno janeiro fevereiro marco abril maio junho julho agosto setembro outubro novembro dezembro].freeze
  TIME_ONLY = /\A\W*(#{TIME_WORDS.join('|')})\b/

  # ➕ BOTÕES do Gerador (15/11/2026, Guilherme: "ir somando aumento de consumo… +1 ar-condicionado, +2, chuveiro,
  # piscina"): a MESMA tabela aprovada acima, um botão por aparelho. Cada toque soma 1 unidade (kWh por mês).
  # chave → { rotulo (1 unidade), plural (2 ou mais), kwh (por unidade), grupo }
  BUTTONS = [
    { 'chave' => 'ar_9', 'rotulo' => 'ar-condicionado (9.000 BTU)', 'plural' => 'ar-condicionados (9.000 BTU)', 'kwh' => 70,
      'curto' => 'Ar 9 mil' },
    { 'chave' => 'ar_12', 'rotulo' => 'ar-condicionado (12.000 BTU)', 'plural' => 'ar-condicionados (12.000 BTU)', 'kwh' => 90,
      'curto' => 'Ar 12 mil' },
    { 'chave' => 'ar_18', 'rotulo' => 'ar-condicionado (18.000 BTU)', 'plural' => 'ar-condicionados (18.000 BTU)', 'kwh' => 120,
      'curto' => 'Ar 18 mil' },
    { 'chave' => 'ar_24', 'rotulo' => 'ar-condicionado (24.000 BTU ou mais)', 'plural' => 'ar-condicionados (24.000 BTU ou mais)',
      'kwh' => 150, 'curto' => 'Ar 24 mil' },
    { 'chave' => 'chuveiro', 'rotulo' => 'chuveiro elétrico', 'plural' => 'chuveiros elétricos', 'kwh' => SHOWER, 'curto' => 'Chuveiro' },
    { 'chave' => 'piscina', 'rotulo' => 'piscina (bomba do filtro)', 'plural' => 'piscinas (bomba do filtro)', 'kwh' => POOL_FILTER,
      'curto' => 'Piscina' },
    { 'chave' => 'piscina_aquecida', 'rotulo' => 'piscina aquecida (bomba de calor)', 'plural' => 'piscinas aquecidas (bomba de calor)',
      'kwh' => POOL_HEAT_PUMP, 'curto' => 'Piscina aquecida' },
    { 'chave' => 'carro', 'rotulo' => 'carro elétrico', 'plural' => 'carros elétricos', 'kwh' => CAR, 'curto' => 'Carro elétrico' },
    { 'chave' => 'geladeira', 'rotulo' => 'geladeira/freezer', 'plural' => 'geladeiras/freezers', 'kwh' => FRIDGE,
      'curto' => 'Geladeira/freezer' },
    { 'chave' => 'hidro', 'rotulo' => 'hidromassagem', 'plural' => 'hidromassagens', 'kwh' => HOT_TUB, 'curto' => 'Hidromassagem' },
    { 'chave' => 'forno', 'rotulo' => 'forno elétrico', 'plural' => 'fornos elétricos', 'kwh' => OVEN, 'curto' => 'Forno elétrico' }
  ].freeze

  def self.parse(text)
    new(text).parse
  end

  def initialize(text)
    @text = I18n.transliterate(text.to_s).downcase.squish
  end

  def parse # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    itens = []
    unknown = nil
    segments.each do |seg|
      found = item_for(seg)
      if found
        itens << found
      elsif !seg.match?(TIME_ONLY) && !seg.match?(/\d\s*km/) && seg.match?(/[a-z]{3,}/)
        unknown ||= seg
      end
    end
    unknown ||= @text if itens.empty?
    { itens: itens, desconhecido: unknown }
  end

  private

  def segments
    @text.split(/\s*(?:,|;|\+|\be\b|\bmais\b|\btambem\b)\s*/).map(&:strip).reject(&:empty?)
  end

  def item_for(seg) # rubocop:disable Metrics/CyclomaticComplexity
    return pool(seg) if seg.include?('piscina')
    return air(seg) if seg.match?(AIR)
    return car(seg) if seg.match?(/carro|veiculo|\bev\b|carregador|wallbox/)
    return each(seg, /chuveiro/, 'chuveiro elétrico', SHOWER).merge('chave' => 'chuveiro') if seg.include?('chuveiro')
    if seg.match?(/geladeira|freezer|frigobar|adega/)
      return each(seg, /geladeira|freezer|frigobar|adega/, 'geladeira/freezer', FRIDGE).merge('chave' => 'geladeira')
    end
    return { 'rotulo' => 'hidromassagem', 'kwh' => HOT_TUB, 'chave' => 'hidro', 'qtd' => 1 } if seg.match?(/hidro|banheira|spa\b|ofuro/)
    return { 'rotulo' => 'forno elétrico', 'kwh' => OVEN, 'chave' => 'forno', 'qtd' => 1 } if seg.include?('forno')

    nil
  end

  def quantity(seg, word)
    rooms = seg.match(ROOMS)
    return rooms[1].to_i.positive? ? rooms[1].to_i : NUMBERS.fetch(rooms[1], 1) if rooms

    found = seg.match(/#{QTY}(?=#{word.source})/)
    return found[1].to_i.positive? ? found[1].to_i : NUMBERS.fetch(found[1], 1) if found

    seg.match?(/\bares\b|condicionados|splits/) ? 2 : 1
  end

  def air(seg)
    qty = quantity(seg, AIR)
    btu = seg[/(\d{1,2})[.\s]?(?:000|mil)\b/, 1]&.to_i&.*(1000)
    kwh = btu ? AR_BY_BTU.find { |limit, _| btu <= limit }.last : AR_UNKNOWN
    label = "#{qty} #{qty > 1 ? 'ar-condicionados' : 'ar-condicionado'}#{" (#{btu.to_fs(:delimited, delimiter: '.')} BTU)" if btu}"
    { 'rotulo' => label, 'kwh' => qty * kwh, 'chave' => AIR_KEYS.fetch(kwh, 'ar_12'), 'qtd' => qty }
  end

  def car(_seg)
    km = @text[/(\d[\d.]*)\s*km/, 1]&.delete('.')&.to_i # o km pode vir em outro trecho ("carro elétrico, rodo 2.000 km")
    return { 'rotulo' => "carro elétrico (#{km.to_fs(:delimited, delimiter: '.')} km por mês)", 'kwh' => (km * CAR_PER_KM).round } if km&.positive?

    { 'rotulo' => 'carro elétrico', 'kwh' => CAR, 'chave' => 'carro', 'qtd' => 1 }
  end

  def pool(seg)
    return nil if seg.include?('resist') # aquecedor de resistência: 800 a 2.000 kWh, fica com o Fernando
    if seg.match?(/aquec|bomba de calor|trocador/)
      return { 'rotulo' => 'piscina aquecida (bomba de calor)', 'kwh' => POOL_HEAT_PUMP, 'chave' => 'piscina_aquecida', 'qtd' => 1 }
    end

    { 'rotulo' => 'piscina (bomba do filtro)', 'kwh' => POOL_FILTER, 'chave' => 'piscina', 'qtd' => 1 }
  end

  def each(seg, word, label, kwh)
    qty = quantity(seg, word)
    { 'rotulo' => qty > 1 ? "#{qty} × #{label}" : label, 'kwh' => qty * kwh, 'qtd' => qty }
  end
end
