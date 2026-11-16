# 🧩 MONTAR NA MÃO (15/11/2026, Guilherme: "o Fernando poder montar o orçamento manualmente: trocar a quantidade de
# placas, 4 para 5 ou 6, outro modelo, outro tamanho de placa, e ver o preço mudar").
#
# Os fornecedores montam o kit pelo CONSUMO (a Bluesun não recebe "quero 6 placas"). Então o sistema pede o kit com o
# consumo que dá exatamente N placas daquele tamanho e confere o que voltou: se a placa escolhida veio com outra
# quantidade, corrige o consumo pela proporção e pede de novo (no máximo TRIES vezes). O preço continua REAL, da
# cotação do fornecedor — nada é estimado.
#
#   Crm::KitQuote::Assembly.new(engine, config).run(panels: 6, watts: 620, grid: 'bifasico', roof: 'ceramica')
#     → o mesmo resultado do Engine, com as opções de 6 placas de 620 W primeiro (marcadas 'montagem' => true) e
#       'montagem' => { 'placas', 'potencia_w', 'marca', 'exatas', 'consumo_equivalente' }
#
# O consumo do cliente (a conta de luz) NÃO muda: a economia do orçamento continua a da conta; só o kit muda.
class Crm::KitQuote::Assembly
  TRIES = 3
  PANELS_RANGE = (1..200)
  WATTS_RANGE = (100..1000)

  def initialize(engine, config)
    @engine = engine
    @config = config
  end

  def run(panels:, watts:, grid:, roof:, brand: nil)
    @panels = panels.to_i
    @watts = watts.to_f
    @brand = brand.to_s.squish.presence
    kwh = first_guess
    result = nil
    TRIES.times do
      result = @engine.run(kwh_month: kwh, grid: grid, roof: roof, margin: false)
      got = count_for_size(result)
      break if got.nil? || got == @panels

      kwh = (kwh * (@panels - 0.5) / (got - 0.5)).round(1)
    end
    finish(result, kwh)
  end

  def self.valid?(panels, watts)
    PANELS_RANGE.cover?(panels.to_i) && WATTS_RANGE.cover?(watts.to_f)
  end

  private

  # o consumo que pede "N − meia placa": no meio da faixa que o fornecedor arredonda para N placas
  def first_guess
    kwp = (@panels - 0.5) * @watts / 1000
    (kwp * @config['incidencia_solar'].to_f * 30 * (1 - @config['perda'].to_f)).round(1)
  end

  def same_size?(option)
    watts = option.dig('equipamento', 'placa', 'potencia_w').to_f
    (watts - @watts).abs < 0.5
  end

  def same_model?(option)
    return false unless same_size?(option)
    return true if @brand.nil?

    option.dig('equipamento', 'placa', 'marca').to_s.casecmp(@brand).zero?
  end

  def exact?(option)
    same_model?(option) && option['placas'].to_i == @panels
  end

  # quantas placas vieram do tamanho pedido (a da marca escolhida primeiro); nil = esse tamanho não veio
  def count_for_size(result)
    options = Array(result['opcoes'])
    return @panels if options.any? { |o| exact?(o) }

    pick = options.find { |o| same_model?(o) } || options.find { |o| same_size?(o) }
    pick && pick['placas'].to_i
  end

  def finish(result, kwh)
    options = Array(result['opcoes']).map { |o| o.merge('montagem' => exact?(o)) }
    exact = options.count { |o| o['montagem'] }
    result.merge(
      'opcoes' => options.sort_by { |o| [o['montagem'] ? 0 : 1, o['total'].to_f] },
      'montagem' => { 'placas' => @panels, 'potencia_w' => @watts.round, 'marca' => @brand, 'exatas' => exact,
                      'consumo_equivalente' => kwh, 'kwp' => (@panels * @watts / 1000).round(2) }
    )
  end
end
