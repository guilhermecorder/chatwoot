# Monta os DADOS dos dois documentos de um orçamento da LIFE — a proposta do cliente e a
# justificativa interna (como se chegou ao preço) — no formato que o gerador de PDF lê
# (LIFE/orcamento/proposta: gerar.py e gerar_justificativa.py; campos no README de lá).
# Todo orçamento sai com os dois (regra do Guilherme, 11/11/2026). Aqui não se desenha nada:
# os números saem do DRE (Crm::KitQuote::Dre), por um único Crm::KitQuote::Budget.
class Crm::KitQuote::Proposal
  CARD = '6x sem juros ou até 20x no cartão (favor nos consultar)'.freeze
  # Economia em 10 e em 25 anos: mesma proporção da proposta do Residencial Potengi (aprovada).
  ECONOMY_10 = 647_000 / 52_800.0
  ECONOMY_25 = 3_774_000 / 52_800.0

  # config + input: ver Crm::KitQuote::Budget#initialize
  def initialize(config:, **input)
    @budget = Crm::KitQuote::Budget.new(config, input)
  end

  def call
    { 'proposta' => proposal, 'justificativa' => Crm::KitQuote::Justification.new(@budget).call }
  end

  private

  def proposal
    {
      'cliente' => client, 'proposta' => { 'data' => @budget.date.iso8601, 'validade_dias' => 7 },
      'conta' => bill, 'telhado' => { 'tipo' => @budget.roof_name }, 'sistema' => system,
      'garantias' => warranties, 'economia' => economy, 'investimento' => investment
    }
  end

  def client
    given = @budget.client
    { 'nome' => given['nome'], 'cidade' => given['cidade'].presence || @budget.config['cidade'],
      'uf' => given['uf'].presence || @budget.config['uf'], 'distribuidora' => 'CPFL' }
  end

  # Com acréscimo, a tela 7 da proposta mostra como a conta foi calculada (conta de hoje + 2 ares).
  def bill
    block = { 'valor_mensal' => @budget.bill_total.round(2), 'consumo_kwh_mes' => @budget.kwh_total.round }
    return block if @budget.additions.empty?

    lines = [{ 'rotulo' => 'Conta de luz hoje', 'valor' => @budget.bill['hoje'].to_f }] +
            @budget.additions.map { |a| { 'rotulo' => a['rotulo'].to_s.squish.presence || 'Consumo que vai aumentar', 'valor' => a['valor'].to_f } }
    block.merge('composicao' => lines)
  end

  def system
    production = @budget.monthly_production
    {
      'potencia_kwp' => @budget.kwp.round(2), 'paineis' => [@budget.panel], 'inversores' => @budget.inverters,
      'producao_kwh_mes' => production, 'producao_kwh_ano' => production * 12,
      'area_m2' => @budget.area, 'peso_kg' => @budget.weight, 'incidencia_solar' => @budget.config['incidencia_solar'].to_f
    }
  end

  def warranties
    [
      { 'item' => 'Placas', 'anos' => 25, 'cobre' => 'de desempenho: no mínimo 80% da potência' },
      { 'item' => 'Placas', 'anos' => 10, 'cobre' => 'contra defeito de fabricação' },
      @budget.inverter_rule['garantia'].merge('cobre' => 'contra defeito de fabricação')
    ]
  end

  # A economia é a conta MENOS a taxa mínima da CPFL, que continua (Guilherme, 13/11/2026: "precisamos descontar a
  # taxa mínima e trazer clareza pro cliente"). A proposta e o resumo mostram a observação com o valor da taxa.
  def economy
    monthly = @budget.monthly_saving
    yearly = monthly * 12
    { 'mensal' => monthly, 'anual' => yearly.round(2),
      'em_10_anos' => @budget.round_to(yearly * ECONOMY_10, 500), 'em_25_anos' => @budget.round_to(yearly * ECONOMY_25, 1000),
      'conta_mensal' => @budget.bill_total.round(2), 'taxa_minima' => minimum_fee_block, 'observacao' => minimum_fee_note }
  end

  def minimum_fee_block
    { 'valor' => @budget.minimum_fee, 'kwh' => @budget.minimum_kwh, 'rede' => Crm::KitQuote::Budget::GRID_NAMES[@budget.grid] }
  end

  # "Sua conta não zera: continua a taxa mínima da CPFL, de R$ 47,50 por mês (...). A economia já está com ela descontada."
  def minimum_fee_note
    "Sua conta de luz não zera: continua a taxa mínima da CPFL, de #{@budget.money(@budget.minimum_fee)} por mês " \
      "(o mínimo de #{@budget.minimum_kwh} kWh que toda ligação #{Crm::KitQuote::Budget::GRID_NAMES[@budget.grid]} paga), " \
      'mais a iluminação pública que já vem na conta. A economia mostrada aqui já está com essa taxa descontada.'
  end

  def investment
    { 'preco_total' => @budget.price, 'preco_antes' => @budget.before_price, 'financiamento' => @budget.financing, 'cartao' => CARD }
  end
end
