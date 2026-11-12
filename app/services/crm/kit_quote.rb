# ☀️ COTADOR DE KITS (LIFE, 11/11/2026)
# Do consumo da conta de luz até as melhores opções de kit, consultando os
# fornecedores (AVT, Bluesun). Os preços são o CUSTO do kit no fornecedor,
# não o preço para o cliente.
#
# Peças:
#   Crm::KitQuote::Engine  — calcula a potência, consulta, escolhe até N opções
#   Crm::KitQuote::Avt     — API oficial (token) ou sessão do portal
#   Crm::KitQuote::Bluesun — sessão do portal
#   Crm::KitQuote::Picker  — escolha das opções
#   Crm::KitQuote::Average — custo do kit: preço médio dos fornecedores com cotação completa
#   Crm::KitQuote::Dre     — DRE projetado, tabela de adequação e regra de preço
#   Crm::KitQuote::Http    — chamada HTTP simples (status + JSON)
module Crm::KitQuote
  # O fornecedor recusou, ou a sessão não existe / venceu.
  # A mensagem já vem pronta para mostrar na tela.
  class NoAccess < StandardError; end

  # O que foi informado na tela de acessos não serve (sessão colada errada etc.).
  class Invalid < StandardError; end

  DEFAULTS = {
    'cidade' => 'Piracicaba',
    'uf' => 'SP',
    'ibge' => '3538709',
    'incidencia_solar' => 4.91,
    'perda' => 0.20,
    'max_opcoes' => 7,
    # R$ por kWh para passar a conta de luz para consumo (mesma relação da proposta do
    # Residencial Potengi: R$ 4.400 para 4.250 kWh). O consumo calculado pode ser ajustado na tela.
    'tarifa' => 1.035,
    # Serviço que transforma os dados do orçamento em PDF (o gerador aprovado, em Python + Chrome).
    # Sem endereço, o sistema monta os dados e avisa que o PDF não pôde ser gerado.
    'gerador_pdf' => { 'url' => nil, 'token' => nil },
    'avt' => {
      'base' => 'https://api-d1297.cloud.solaryum.com.br',
      'id_cliente' => nil,
      'id_fornecedor' => 2,
      'percentual' => 2
    },
    'bluesun' => {
      'api' => 'https://api.bluesundobrasil.com.br',
      'id_empresa' => 'LIMEIRA',
      'id_municipio' => 3701,
      # Estrutura de cada tipo de telhado (linha FotoFIX Tradicional), lida em 11/11/2026 de
      # GET /v1/orcamentos/geracao/estruturas/LIMEIRA. Outras linhas do mesmo telhado:
      # cerâmica 43 (Solar Group) e 14 (FotoFIX Premium); fibrocimento 44/45 (Solar Group), 15/2 (Premium);
      # metálica 46 (Solar Group). Solo (9, 32, 33, 34) fica fora: tem regra própria de instalação.
      'estruturas' => { 'ceramica' => 47, 'fibrocimento_madeira' => 50, 'fibrocimento_metalica' => 49, 'metalica' => 48, 'laje' => 4 }
    }
  }.freeze

  # Tipos de telhado que a tela oferece (chave → nome que vai na proposta).
  ROOFS = {
    'ceramica' => 'Telha cerâmica',
    'fibrocimento_madeira' => 'Fibrocimento com viga de madeira',
    'fibrocimento_metalica' => 'Fibrocimento com viga metálica',
    'metalica' => 'Telha metálica',
    'laje' => 'Laje'
  }.freeze

  GRIDS = %w[monofasico bifasico trifasico].freeze
  PARALLEL = 4

  module_function

  # Roda os blocos ao mesmo tempo e devolve os resultados na mesma ordem.
  # As consultas aos fornecedores são lentas (segundos cada) e a requisição
  # da tela tem limite de tempo, então nada de uma depois da outra.
  # No máximo PARALLEL de cada vez: muitas ao mesmo tempo derrubam a busca de
  # endereço dentro do contêiner.
  def together(jobs)
    jobs.each_slice(PARALLEL).flat_map do |slice|
      threads = slice.map { |job| Thread.new { job.call } }
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads { threads.map(&:value) }
    end
  end

  # kWp para cobrir o consumo: consumo / (sol do dia × 30 dias × aproveitamento)
  def needed_kwp(kwh_month, sun, loss)
    kwh_month.to_f / (sun.to_f * 30 * (1 - loss.to_f))
  end

  def panels_for(kwp, panel_watts)
    [(kwp.to_f * 1000 / panel_watts.to_f).ceil, 1].max
  end

  # Formato único de uma opção, igual para todos os fornecedores.
  # attrs: supplier, type (string | micro | hibrido), kwp, panels, panel_count, inverter, price,
  #        freight (nil = o fornecedor não informou), structure (true = o preço inclui a estrutura do telhado),
  #        equipment (marca e potência separadas, quando o fornecedor informa), note
  # 'completa' = kit + estrutura do telhado + frete: só essas entram no preço médio do kit.
  def option(**attrs)
    kwp = attrs[:kwp].to_f
    price = attrs[:price].to_f
    description(attrs).merge(
      'potencia_kwp' => kwp.round(2), 'preco' => price.round(2),
      'preco_por_kwp' => kwp.positive? ? (price / kwp).round(2) : nil
    ).merge(completeness(price, attrs[:freight], attrs[:structure]))
  end

  def description(attrs)
    {
      'fornecedor' => attrs[:supplier],
      'tipo' => attrs[:type],
      'placas' => attrs[:panel_count].to_i,
      'paineis' => attrs[:panels].to_s.squish,
      'inversor' => attrs[:inverter].to_s.squish.gsub(/\A[\s-]+|[\s-]+\z/, ''),
      'obs' => attrs[:note].to_s,
      # { 'placa' => { quantidade, marca, potencia_w }, 'inversores' => [{ quantidade, marca, potencia_kw }], 'peso_kg' }
      'equipamento' => attrs[:equipment]
    }
  end

  def completeness(price, freight, structure)
    missing = [('estrutura do telhado' unless structure), ('frete' if freight.nil?)].compact
    {
      'frete' => freight&.to_f&.round(2),
      'estrutura' => structure ? true : false,
      'total' => (price + freight.to_f).round(2),
      'completa' => missing.empty?,
      'falta' => missing.join(' e ')
    }
  end

  # R$ 7.020,71
  def money(value)
    ActiveSupport::NumberHelper.number_to_currency(value.to_f, unit: 'R$ ', separator: ',', delimiter: '.', precision: 2)
  end
end
