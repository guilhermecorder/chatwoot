# DRE projetado de um orçamento da LIFE, igual à planilha
# "SC Consultoria - Cálculo Orçamento - FRANQUIA" (aba DRE GERAL + regras da aba base),
# com os ajustes ditos pelo Guilherme em 11/11/2026:
#
#   Dedutíveis    Kit gerador · Instalação (R$ 100 por placa) · Adequação (tabela por tipo de
#                 inversor e número de placas) · Representante c/ NF (comissão: 0%, os vendedores
#                 são os sócios) · Rota
#   Imposto       10% sobre (Valor do projeto − Dedutíveis)
#   Indedutíveis  PLL 2% · Brinde R$ 78 · Sicredi · Representante s/ NF · Homologação R$ 450 ·
#                 Operacional · Outros   (o seguro saiu: a Life não oferece mais; vira lucro)
#   Lucro líquido Valor do projeto − Indedutíveis − Imposto − Dedutíveis
#
# Regras de preço:
#   - o custo do kit é o preço MÉDIO entre os fornecedores com cotação completa
#     (kit + estrutura do telhado + frete);
#   - o orçamento padrão sai com 25% de lucro líquido, arredondado para cima de R$ 10 em R$ 10;
#   - a faixa esperada é de 18% a 30% (fora dela a tela avisa).
#
# O mesmo cálculo existe em LIFE/orcamento/dre/gerar_dre.py (gerador dos PDFs). Mudou aqui, muda lá.
class Crm::KitQuote::Dre
  # A tabela de adequação não cobre esse tipo de inversor / número de placas:
  # não se inventa valor, a tela pede o valor manual.
  class NoAdequacyBand < StandardError; end

  RULES = {
    'instalacao_por_placa' => 100.0, 'comissao' => 0.0, 'imposto' => 0.10, 'pll' => 0.02,
    'brinde' => 78.0, 'sicredi' => 0.0, 'representante_sem_nf' => 0.0, 'homologacao' => 450.0,
    'operacional' => 0.0, 'rota' => 0.0, 'outros' => 0.0
  }.freeze
  STANDARD_MARGIN = 0.25
  RANGE = (0.18..0.30)
  PARTNERS = { 'Vini' => 0.04, 'Ac' => 0.38, 'Fernando' => 0.29, 'Guilherme' => 0.29 }.freeze
  PERCENT_OF_PRICE = %w[pll sicredi representante_sem_nf operacional].freeze

  # TABELA DE ADEQUAÇÃO (planilha "ADEQUAÇÃO", passada pelo Guilherme em 11/11/2026):
  # [de, até, valor, faixa como está escrita na planilha]. A planilha repete o 70 e o 100
  # em duas faixas; aqui vale a primeira (70 placas = faixa "47 a 70").
  ADEQUACY = {
    'micro' => [[4, 8, 550.0, '4 a 8'], [9, 12, 700.0, '9 a 12'], [13, 16, 950.0, '13 a 16'],
                [17, 20, 1000.0, '17 a 20'], [21, 32, 1250.0, '21 a 32']],
    'string' => [[4, 8, 760.0, '4 a 8'], [9, 12, 950.0, '9 a 12'], [13, 16, 1000.0, '13 a 16'],
                 [17, 20, 1200.0, '17 a 20'], [21, 32, 1450.0, '21 a 32'], [33, 46, 1800.0, '33 a 46'],
                 [47, 70, 2500.0, '47 a 70'], [71, 100, 3190.0, '70 a 100'], [101, 200, 5276.0, '100 a 200']]
  }.freeze
  INVERTER_NAMES = { 'micro' => 'micro inversor', 'string' => 'inversor string' }.freeze

  # { 'valor' => 550.0, 'faixa' => 'micro inversor, 4 a 8 placas' } ou nil quando a tabela não cobre.
  def self.adequacy(type, panels)
    band = ADEQUACY.fetch(type.to_s, []).find { |from, to, _value, _label| panels.to_i.between?(from, to) }
    band && { 'valor' => band[2], 'faixa' => "#{INVERTER_NAMES[type.to_s]}, #{band[3]} placas" }
  end

  # kits: [{ 'fornecedor' => 'Bluesun', 'valor' => 7178.80 }, ...]
  # panels: quantidade de placas · type: 'micro' | 'string'
  # adequacy: valor manual da adequação (nil = usa a tabela)
  def initialize(kits:, panels:, type: nil, adequacy: nil, rules: {})
    @kits = Array(kits).map { |k| { 'fornecedor' => k['fornecedor'].to_s, 'valor' => k['valor'].to_f } }.select { |k| k['valor'].positive? }
    @panels = panels.to_i
    @type = type.to_s
    @manual_adequacy = adequacy.presence && adequacy.to_f
    @rules = RULES.merge((rules || {}).slice(*RULES.keys).transform_values(&:to_f))
  end

  def kit_cost
    return 0.0 if @kits.empty?

    @kits.sum { |k| k['valor'] } / @kits.size
  end

  # Valor e origem da adequação: manual quando informado, senão a tabela.
  def adequacy
    @adequacy ||= if @manual_adequacy
                    { 'valor' => @manual_adequacy, 'faixa' => 'valor manual', 'manual' => true }
                  else
                    (self.class.adequacy(@type, @panels) || no_band!).merge('manual' => false)
                  end
  end

  # Valor do projeto que entrega a margem líquida pedida.
  def price_for(margin)
    factor = ((1 - @rules['imposto']) * (1 - @rules['comissao'])) - PERCENT_OF_PRICE.sum { |k| @rules[k] }
    (((1 - @rules['imposto']) * fixed_deductible) + fixed_non_deductible) / (factor - margin)
  end

  # Preço do orçamento para a margem: arredondado para cima de R$ 10 em R$ 10 (padrão: 25%).
  def standard_price(margin = STANDARD_MARGIN)
    (price_for(margin) / 10).ceil * 10
  end

  # price: preço ajustado na mão · margin: margem escolhida (0.30) · sem nada: o padrão de 25%.
  def result(price = nil, margin: nil)
    price = chosen_price(price, margin)
    deductible = deductible_lines(price)
    non_deductible = non_deductible_lines(price)
    tax = (price - total(deductible)) * @rules['imposto']
    summary(price, price - total(deductible) - total(non_deductible) - tax).merge(inputs).merge(
      'imposto' => tax.round(2), 'taxa_imposto' => @rules['imposto'],
      'dedutiveis' => round(deductible), 'total_dedutiveis' => total(deductible).round(2),
      'indedutiveis' => round(non_deductible), 'total_indedutiveis' => total(non_deductible).round(2)
    )
  end

  private

  def chosen_price(price, margin)
    return price.to_f if price.to_f.positive?

    standard_price(margin.to_f.positive? ? margin.to_f : STANDARD_MARGIN).to_f
  end

  def inputs
    { 'kits' => @kits, 'custo_kit' => kit_cost.round(2), 'placas' => @panels, 'tipo' => @type, 'adequacao' => adequacy }
  end

  def no_band!
    name = INVERTER_NAMES[@type] || 'tipo de inversor não informado'
    raise NoAdequacyBand, "A tabela de adequação não tem faixa para #{@panels} placas com #{name}. Informe o valor da adequação."
  end

  def fixed_deductible
    kit_cost + (@rules['instalacao_por_placa'] * @panels) + adequacy['valor'] + @rules['rota']
  end

  def fixed_non_deductible
    @rules['brinde'] + @rules['homologacao'] + @rules['outros']
  end

  def deductible_lines(price)
    [
      line("Kit gerador (média de #{@kits.size} #{@kits.size == 1 ? 'fornecedor' : 'fornecedores'})", kit_cost),
      line("Instalação (#{@panels} placas)", @rules['instalacao_por_placa'] * @panels),
      line("Adequação (#{adequacy['faixa']})", adequacy['valor']),
      line('Representante c/ NF (comissão)', @rules['comissao'] * price, @rules['comissao']),
      line('Rota', @rules['rota'])
    ]
  end

  def non_deductible_lines(price)
    [
      line('PLL', @rules['pll'] * price, @rules['pll']),
      line('Brinde', @rules['brinde']), line('Sicredi', @rules['sicredi'] * price, @rules['sicredi']),
      line('Representante s/ NF', @rules['representante_sem_nf'] * price, @rules['representante_sem_nf']),
      line('Homologação', @rules['homologacao']), line('Operacional', @rules['operacional'] * price, @rules['operacional']),
      line('Outros', @rules['outros'])
    ]
  end

  def summary(price, profit)
    margin = price.positive? ? profit / price : 0.0
    {
      'valor_projeto' => price.round(2), 'lucro' => profit.round(2), 'margem' => margin.round(4),
      'custo_total' => (price - profit).round(2),
      'na_faixa' => margin.between?(RANGE.begin - 0.0005, RANGE.end + 0.0005),
      'padrao' => standard_price,
      'faixa' => { 'minimo' => price_for(RANGE.begin).round(2), 'padrao' => price_for(STANDARD_MARGIN).round(2),
                   'maximo' => price_for(RANGE.end).round(2) },
      'socios' => PARTNERS.map { |name, share| { 'nome' => name, 'parte' => share, 'valor' => (profit * share).round(2) } }
    }
  end

  def line(name, value, rate = nil)
    { 'nome' => name, 'valor' => value.to_f, 'taxa' => rate }
  end

  def total(lines)
    lines.sum { |l| l['valor'] }
  end

  def round(lines)
    lines.map { |l| l.merge('valor' => l['valor'].round(2)) }
  end
end
