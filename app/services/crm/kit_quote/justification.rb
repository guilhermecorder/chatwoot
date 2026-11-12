# A JUSTIFICATIVA do orçamento (documento interno, para sócios e equipe): como se chegou ao
# preço. Consumo → sistema → cotações e média → custos do DRE (com a adequação e a faixa
# usada) → preço e lucro (faixa de 18/25/30% e lucro por sócio) → o que conferir.
# Sai sempre junto com a proposta (Crm::KitQuote::Proposal), com os mesmos números.
class Crm::KitQuote::Justification
  SUPPLIERS = %w[AVT Bluesun Belenergy Cordeiro].freeze # onde a planilha manda cotar
  SOURCE = 'Planilha SC Consultoria - Cálculo Orçamento - FRANQUIA (aba DRE GERAL e regras da aba base), ' \
           'tabela de adequação e cotações feitas no Gerador de proposta em %<date>s'.freeze

  def initialize(budget)
    @budget = budget
    @dre = budget.dre
  end

  def call
    client = @budget.client
    {
      'cliente' => client['nome'],
      'cidade' => "#{client['cidade'].presence || @budget.config['cidade']}/#{client['uf'].presence || @budget.config['uf']}",
      'data' => @budget.date.iso8601, 'resumo' => @dre.slice('valor_projeto', 'custo_total', 'lucro', 'margem'),
      'consumo' => consumption, 'sistema' => sizing, 'kit' => kit, 'adequacao' => @dre['adequacao'],
      'custos' => costs, 'preco' => pricing, 'conferir' => checklist,
      'fonte' => format(SOURCE, date: @budget.date.strftime('%d/%m/%Y'))
    }
  end

  private

  def consumption
    note = "A tarifa de R$ #{@budget.decimal(@budget.tariff, 3)} por kWh é a referência da Life para a conta da CPFL " \
           '(valor da conta ÷ tarifa = consumo em kWh).'
    note += ' O consumo que vai aumentar é estimativa.' if @budget.additions.any?
    { 'linhas' => consumption_lines, 'total_reais' => @budget.bill_total.round(2), 'total_kwh' => @budget.kwh_total.round,
      'tarifa' => @budget.tariff, 'nota' => note }
  end

  # A conta de hoje vira kWh pela tarifa; o que vai aumentar fica com o resto do consumo informado.
  def consumption_lines
    today = @budget.bill['hoje'].to_f
    first = { 'rotulo' => 'Conta de luz hoje', 'reais' => today, 'kwh' => @budget.kwh_today,
              'nota' => "#{@budget.short_money(today)} ÷ R$ #{@budget.decimal(@budget.tariff, 3)} por kWh" }
    [first] + addition_lines(@budget.kwh_total - @budget.kwh_today)
  end

  def addition_lines(extra_kwh)
    total = @budget.additions.sum { |a| a['valor'].to_f }
    @budget.additions.map do |a|
      { 'rotulo' => a['rotulo'].to_s.squish, 'reais' => a['valor'].to_f, 'kwh' => (extra_kwh * a['valor'].to_f / total).round,
        'nota' => 'estimativa' }
    end
  end

  def sizing
    config = @budget.config
    use = ((1 - config['perda'].to_f) * 100).round
    production = @budget.monthly_production
    {
      'formula' => "#{@budget.kwh_total.round} kWh ÷ (#{@budget.decimal(config['incidencia_solar'])} h de sol × 30 dias × " \
                   "#{use}% de aproveitamento) = #{@budget.decimal(@budget.needed_kwp)} kWp",
      'potencia_necessaria_kwp' => @budget.needed_kwp.round(2), 'placas' => @budget.panels,
      'potencia_placa_w' => @budget.panel['potencia_w'], 'potencia_kwp' => @budget.kwp.round(2), 'producao_kwh_mes' => production,
      'cobertura' => (production / @budget.kwh_total).round(2), 'equipamento' => @budget.equipment_text
    }
  end

  def kit
    quotes = @budget.quotes
    {
      'regra' => 'Preço médio dos fornecedores com cotação completa (kit + estrutura + frete)',
      'cotacoes' => quotes.map { |q| q.slice('fornecedor', 'valor', 'detalhe', 'entra_na_media') },
      'nao_cotados' => SUPPLIERS - quotes.pluck('fornecedor'),
      'media' => @dre['custo_kit'], 'fornecedores_na_media' => quotes.count { |q| q['entra_na_media'] }
    }
  end

  # Só as linhas com valor; o imposto entra no meio, como na planilha. Os centavos de
  # arredondamento vão para a última linha, para a soma dar exatamente o custo total.
  def costs
    lines = (nonzero(@dre['dedutiveis']) + [tax_line] + nonzero(@dre['indedutiveis'])).map { |l| l.slice('nome', 'valor', 'taxa') }
    gap = (@dre['custo_total'] - lines.sum { |l| l['valor'] }).round(2)
    lines.last['valor'] = (lines.last['valor'] + gap).round(2) unless gap.zero?
    lines
  end

  def nonzero(lines)
    lines.reject { |l| l['valor'].zero? }
  end

  def tax_line
    rate = @dre['taxa_imposto']
    { 'nome' => "Imposto (#{@budget.percent(rate)} sobre valor menos dedutíveis)", 'valor' => @dre['imposto'], 'taxa' => rate }
  end

  def pricing
    price = @budget.price
    {
      'regra' => price_rule, 'valor_projeto' => price, 'lucro' => @dre['lucro'], 'margem' => @dre['margem'],
      'faixa' => margin_rows, 'socios' => @dre['socios'], 'por_kwp' => @budget.kwp.positive? ? (price / @budget.kwp).round(2) : 0
    }
  end

  def price_rule
    base = if @budget.standard?
             "Orçamento padrão com #{@budget.percent(Crm::KitQuote::Dre::STANDARD_MARGIN)} de lucro líquido, " \
               'arredondado para cima de R$ 10 em R$ 10.'
           else
             "Preço ajustado: #{@budget.money(@budget.price)}, lucro líquido de #{@budget.percent(@dre['margem'])} " \
               "(o padrão de 25% seria #{@budget.money(@dre['padrao'])})."
           end
    "#{base} Sem comissão e sem seguro; imposto de #{@budget.percent(@dre['taxa_imposto'])}."
  end

  # As três pontas da faixa (18%, 25%, 30%) e, quando o preço foi ajustado, a linha do preço escolhido.
  def margin_rows
    range = Crm::KitQuote::Dre::RANGE
    rows = { range.begin => 'minimo', Crm::KitQuote::Dre::STANDARD_MARGIN => 'padrao', range.end => 'maximo' }.map do |margin, key|
      { 'margem' => margin, 'valor' => @dre.dig('faixa', key), 'padrao' => false }
    end
    return rows.tap { |r| r[1].merge!('padrao' => true, 'selo' => 'Padrão') } if @budget.standard?

    (rows << { 'margem' => @dre['margem'], 'valor' => @budget.price, 'padrao' => true, 'selo' => 'Escolhido' }).sort_by { |r| r['margem'] }
  end

  def checklist
    [additions_check, adequacy_check, quotes_check, range_check, financing_check, warranty_check, before_check].compact
  end

  def additions_check
    additions = @budget.additions
    "Consumo que vai aumentar (#{additions.pluck('rotulo').join(', ')}) é estimativa: confirmar com o cliente." if additions.any?
  end

  # O Guilherme pediu: a adequação sempre descrita, com a faixa usada e o valor.
  def adequacy_check
    adequacy = @dre['adequacao']
    return "Adequação informada na mão: #{@budget.money(adequacy['valor'])} (a tabela não tem faixa para este projeto)." if adequacy['manual']

    "Adequação pela tabela: #{adequacy['faixa']} = #{@budget.money(adequacy['valor'])}."
  end

  def quotes_check
    inside, outside = @budget.quotes.partition { |q| q['entra_na_media'] }
    text = "Kit: média de #{inside.size} #{inside.size == 1 ? 'fornecedor' : 'fornecedores'} com cotação completa " \
           "(#{inside.pluck('fornecedor').join(', ')})."
    outside.any? ? "#{text} Fora da média: #{outside.pluck('fornecedor').join(', ')} (cotação sem estrutura ou sem frete)." : text
  end

  def range_check
    "ATENÇÃO: lucro de #{@budget.percent(@dre['margem'])}, fora da faixa de 18% a 30%." unless @dre['na_faixa']
  end

  def financing_check
    list = @budget.financing.map { |f| "#{f['parcelas']}x #{@budget.short_money(f['valor'])}" }.join(', ')
    "Parcelas a #{@budget.percent(Crm::KitQuote::Budget::FINANCING_RATE)} ao mês (taxa a confirmar): #{list}."
  end

  def warranty_check
    rule = @budget.inverter_rule
    "Garantia do inversor (#{rule.dig('garantia', 'anos')} anos): confirmar com o fabricante." if rule['confirmar']
  end

  def before_check
    before = @budget.before_price
    "Preço de antes (#{@budget.short_money(before['de'])} a #{@budget.short_money(before['ate'])}): regra provisória."
  end
end
