# Os números de um orçamento que a proposta e a justificativa compartilham: conta, consumo,
# tamanho do sistema, equipamento, preço (do DRE) e parcelas. Um lugar só, para os dois
# documentos nunca divergirem.
class Crm::KitQuote::Budget
  FINANCING_RATE = 0.035 # ao mês, da planilha (aba base); a taxa ainda vai ser conferida pelo Guilherme
  TERMS = [36, 48, 60].freeze
  AREA_PER_PANEL = 2.84 # m² por placa (193 m² para 68 placas)
  WEIGHT_PER_PANEL = 37.3 # kg por placa com estrutura, quando o fornecedor não informa o peso do kit
  # Preço "de antes" (tela do salto no tempo): R$ por kWp, a mesma relação usada no caso da Adriana.
  # Regra provisória, vai para "O que conferir".
  BEFORE_PER_KWP = [8400, 11_300].freeze
  INVERTERS = {
    'micro' => { 'tipo' => 'Microinversor', 'garantia' => { 'item' => 'Microinversores', 'anos' => 12 } },
    'string' => { 'tipo' => 'Inversor', 'garantia' => { 'item' => 'Inversor', 'anos' => 10 }, 'confirmar' => true }
  }.freeze

  attr_reader :config, :client, :bill, :option, :quotes, :dre, :date

  # config: Crm::KitQuote::DEFAULTS já mesclado. input:
  #   client: { 'nome', 'cidade', 'uf' }
  #   bill:   { 'hoje' => 300, 'acrescimos' => [{ 'rotulo' => '2 ares-condicionados', 'valor' => 200 }], 'consumo_kwh' => 490 }
  #   roof:   chave de Crm::KitQuote::ROOFS · option: a opção escolhida (formato de Crm::KitQuote.option)
  #   quotes: [{ 'fornecedor', 'valor', 'detalhe', 'entra_na_media' }] · dre: resultado de Crm::KitQuote::Dre#result
  #   date:   data da proposta (padrão: hoje)
  def initialize(config, input)
    @config = config
    @client = input.fetch(:client)
    @bill = input.fetch(:bill)
    @roof = input[:roof]
    @option = input.fetch(:option)
    @quotes = input.fetch(:quotes)
    @dre = input.fetch(:dre)
    @date = input[:date] || Time.zone.today
  end

  # ---------- formatação

  def money(value)
    Crm::KitQuote.money(value)
  end

  # R$ 300 (sem os centavos quando são zero)
  def short_money(value)
    money(value).delete_suffix(',00')
  end

  def decimal(value, digits = 2)
    ActiveSupport::NumberHelper.number_to_rounded(value.to_f, precision: digits, separator: ',', delimiter: '.')
  end

  # 0.25 → "25%" · 0.2502 → "25,02%" · 0.035 → "3,5%"
  def percent(fraction)
    "#{decimal(fraction.to_f * 100, 2).sub(/,?0+\z/, '')}%"
  end

  # ---------- conta e consumo

  def tariff
    config['tarifa'].to_f
  end

  def additions
    Array(bill['acrescimos']).select { |a| a['valor'].to_f.positive? }
  end

  def bill_total
    bill['hoje'].to_f + additions.sum { |a| a['valor'].to_f }
  end

  # 💡 A CONTA NÃO ZERA (Guilherme, 13/11/2026): com energia solar continua a taxa mínima da CPFL (custo de
  # disponibilidade da ANEEL: 30 kWh na ligação monofásica, 50 na bifásica, 100 na trifásica) — a economia mostrada
  # ao cliente já vem com ela descontada. Sem a rede informada, bifásica (a mais comum nas casas).
  MINIMUM_KWH = { 'monofasico' => 30, 'bifasico' => 50, 'trifasico' => 100 }.freeze
  GRID_NAMES = { 'monofasico' => 'monofásica', 'bifasico' => 'bifásica', 'trifasico' => 'trifásica' }.freeze

  def grid
    MINIMUM_KWH.key?(bill['rede'].to_s) ? bill['rede'].to_s : 'bifasico'
  end

  def minimum_kwh
    MINIMUM_KWH.fetch(grid)
  end

  def minimum_fee
    (minimum_kwh * tariff).round(2)
  end

  # o que o cliente deixa de pagar por mês: a conta (com os acréscimos) menos a taxa mínima que continua
  def monthly_saving
    [bill_total - minimum_fee, 0].max.round(2)
  end

  # O consumo informado na tela; sem ele, a conta inteira dividida pela tarifa.
  def kwh_total
    bill['consumo_kwh'].to_f.positive? ? bill['consumo_kwh'].to_f : (bill_total / tariff).round
  end

  def kwh_today
    [(bill['hoje'].to_f / tariff).round, kwh_total].min
  end

  # ---------- sistema

  def needed_kwp
    Crm::KitQuote.needed_kwp(kwh_total, config['incidencia_solar'], config['perda'])
  end

  def kwp
    option['potencia_kwp'].to_f
  end

  def panels
    option['placas'].to_i
  end

  def monthly_production
    (kwp * config['incidencia_solar'].to_f * 30 * (1 - config['perda'].to_f)).round
  end

  def type
    INVERTERS.key?(option['tipo']) ? option['tipo'] : 'string'
  end

  def inverter_rule
    INVERTERS[type]
  end

  def roof_name
    Crm::KitQuote::ROOFS[@roof] || 'Telhado a confirmar'
  end

  def weight
    (option.dig('equipamento', 'peso_kg').presence || (panels * WEIGHT_PER_PANEL)).to_f.round
  end

  def area
    (panels * AREA_PER_PANEL).round
  end

  # { 'quantidade' => 7, 'marca' => 'Helius', 'potencia_w' => 630 }
  def panel
    known = option.dig('equipamento', 'placa') || {}
    watts = known['potencia_w'].presence || (panels.positive? ? (kwp * 1000 / panels).round : nil)
    { 'quantidade' => panels, 'marca' => known['marca'].presence || text_after_count(option['paineis']), 'potencia_w' => watts }
  end

  # [{ 'quantidade' => 2, 'tipo' => 'Microinversor', 'marca' => 'Growatt', 'modelo' => '2,5K' }]
  def inverters
    known = Array(option.dig('equipamento', 'inversores'))
    return [{ 'quantidade' => 1, 'tipo' => inverter_rule['tipo'], 'marca' => text_after_count(option['inversor']) }] if known.empty?

    known.map do |i|
      model = i['potencia_kw'] && "#{decimal(i['potencia_kw'], 2).sub(/,?0+\z/, '')}K"
      { 'quantidade' => i['quantidade'].to_i, 'tipo' => inverter_rule['tipo'], 'marca' => i['marca'], 'modelo' => model }.compact
    end
  end

  # "7 placas Helius 630 W + 2 microinversores Growatt 2,5K + estrutura para telha cerâmica"
  def equipment_text
    parts = inverters.map do |i|
      name = i['tipo'].downcase + (i['quantidade'] > 1 ? 'es' : '')
      "#{i['quantidade']} #{name} #{i['marca']} #{i['modelo']}".squish
    end
    "#{panels} placas #{panel['marca']} #{panel['potencia_w']} W + #{parts.join(' + ')} + estrutura para #{roof_name.downcase}"
  end

  # ---------- dinheiro

  def price
    dre['valor_projeto'].to_f
  end

  def standard?
    price.round == dre['padrao'].to_i
  end

  def financing
    TERMS.map do |months|
      { 'parcelas' => months, 'valor' => (price * FINANCING_RATE / (1 - ((1 + FINANCING_RATE)**-months))).round }
    end
  end

  def before_price
    { 'de' => round_to(kwp * BEFORE_PER_KWP.first, 1000), 'ate' => round_to(kwp * BEFORE_PER_KWP.last, 1000) }
  end

  def round_to(value, step)
    (value / step).round * step
  end

  private

  # "7 × Painel 630Wp Helius" → "Painel 630Wp Helius"
  def text_after_count(text)
    text.to_s.sub(/\A\d+\s*[×x]\s*/, '').truncate(40, omission: '')
  end
end
