# ⚡ ORÇAMENTO AUTOMÁTICO (LIFE, 12/11/2026 · pedido do Guilherme): "já gerar automático para a pessoa: já estou gerando o
# seu orçamento, em alguns segundos te mando... e se o sistema do fornecedor tiver fora, vou precisar de alguns minutos".
# Faz no servidor o que o vendedor faz na tela do Gerador: ficha do cliente → cotação nos fornecedores → opção completa
# mais barata (micro inversor primeiro) → preço com 25% → proposta em PDF → guarda no cliente. NÃO envia: quem envia é o
# Crm::KitQuoteAutoJob (Crm::KitQuote::Delivery), e na falha ele avisa o cliente e abre a tarefa para o humano.
#
#   Crm::KitQuote::AutoBuild.new(account, contact).call
#     → Result(status: :pronto, quote: Crm::Quote)
#     → Result(status: :falta_dados | :com_aumento | :fornecedor_fora | :erro, motivo: '...')
# Aumento de consumo previsto (ar, carro elétrico, piscina...) entra pela tabela aprovada (Crm::KitQuote::Increase);
# o que a tabela não cobre (:com_aumento) fica com o Fernando.
class Crm::KitQuote::AutoBuild
  Result = Struct.new(:status, :quote, :motivo, keyword_init: true) do
    def ok?
      status == :pronto
    end
  end
  TYPE_ORDER = %w[micro string].freeze
  GRID = 'bifasico'.freeze

  def initialize(account, contact)
    @account = account
    @contact = contact
  end

  # o que impede de começar (nil = pode gerar). Usado também pela ferramenta do atendente antes de prometer.
  def self.missing(contact)
    data = Crm::KitQuote::ClientData.new(contact).call
    return 'falta o valor da conta de luz na ficha do cliente' unless data['hoje'].positive?
    return 'falta o tipo de telhado na ficha do cliente' if data['telhado'].blank?

    nil
  end

  def call
    problem = self.class.missing(@contact)
    return fail_with(:falta_dados, problem) if problem

    unknown = increase[:desconhecido]
    return fail_with(:com_aumento, "aumento de consumo fora da tabela (#{unknown}): o Fernando estima") if unknown

    build
  rescue Crm::KitQuote::Dre::NoAdequacyBand => e
    fail_with(:erro, "adequação sem faixa na tabela: #{e.message}")
  rescue Crm::KitQuote::NoAccess => e
    fail_with(:fornecedor_fora, e.message)
  rescue StandardError => e
    Rails.logger.error "[Crm::KitQuote::AutoBuild] #{e.class}: #{e.message}"
    fail_with(:erro, "#{e.class}: #{e.message.truncate(120)}")
  end

  private

  def build # rubocop:disable Metrics/AbcSize
    result = Crm::KitQuote::Engine.new(store.config, store.secrets, store).run(kwh_month: kwh, grid: GRID, roof: data['telhado'])
    option = best_option(result['opcoes'])
    return fail_with(:fornecedor_fora, 'nenhum fornecedor trouxe kit completo (kit + estrutura + frete)') unless option

    quotes = quotes_for(result['medias'], option)
    dre = calculator(quotes, option).result(nil, margin: Crm::KitQuote::Dre::STANDARD_MARGIN)
    documents = Crm::KitQuote::Proposal.new(
      config: store.config, client: client, bill: bill, roof: data['telhado'], option: option, quotes: quotes, dre: dre
    ).call
    files = render(documents)
    return fail_with(:erro, @render_error || 'o gerador de PDF não respondeu') if files.blank?

    quote = Crm::KitQuote::Save.call(
      account: @account, contact: @contact, user: nil, documents: documents, dre: dre, files: files,
      floor: floor(quotes, option),
      input: { 'cliente' => client, 'conta' => bill, 'telhado' => data['telhado'], 'opcao' => option, 'cotacoes' => quotes,
               'automatico' => true }
    )
    Result.new(status: :pronto, quote: quote)
  end

  def data
    @data ||= Crm::KitQuote::ClientData.new(@contact).call
  end

  def store
    @store ||= Crm::KitQuote::Store.new(@account)
  end

  # 🔌 o que o cliente vai acrescentar, pela tabela aprovada (Crm::KitQuote::Increase); sem aumento, nada
  def increase
    @increase ||= data['aumento'] ? Crm::KitQuote::Increase.parse(data['aumento']) : { itens: [], desconhecido: nil }
  end

  def tariff
    store.config['tarifa'].to_f
  end

  # consumo de hoje (kWh da ficha ou a conta pela tarifa — igual à tela) + o aumento previsto
  def kwh
    today = if data['kwh'].between?(30, 100_000)
              data['kwh']
            else
              tariff.positive? ? (data['hoje'] / tariff).round : 0
            end
    today + increase[:itens].sum { |i| i['kwh'] }
  end

  # o aumento entra como acréscimo na conta, em reais (igual ao "O que vai acrescentar" da tela)
  def additions
    increase[:itens].map { |i| { 'rotulo' => i['rotulo'], 'valor' => (i['kwh'] * tariff).round(2) } }
  end

  # a opção COMPLETA mais barata, micro inversor primeiro (é o padrão da tela)
  def best_option(options)
    TYPE_ORDER.each do |type|
      found = Array(options).select { |o| o['tipo'] == type && o['completa'] }.min_by { |o| o['total'].to_f }
      return found if found
    end
    nil
  end

  # a opção escolhida vale pelo fornecedor dela; dos outros, a cotação que a média separou (proposalBuilder.quotesFor)
  def quotes_for(averages, option)
    chosen = { 'fornecedor' => option['fornecedor'], 'valor' => option['total'], 'detalhe' => Crm::KitQuote::Average.detail(option),
               'entra_na_media' => option['completa'] == true }
    others = Array(averages&.dig(option['tipo'], 'cotacoes')).reject { |q| q['fornecedor'] == option['fornecedor'] }.map do |q|
      q.slice('fornecedor', 'valor', 'detalhe').merge('entra_na_media' => q['entra_na_media'] == true)
    end
    [chosen, *others]
  end

  def calculator(quotes, option)
    Crm::KitQuote::Dre.new(kits: quotes.select { |q| q['entra_na_media'] }, panels: option['placas'], type: option['tipo'])
  end

  def floor(quotes, option)
    { 'margem' => 0.2, 'valor' => calculator(quotes, option).result(nil, margin: 0.2)['valor_projeto'] }
  rescue StandardError
    nil
  end

  def client
    { 'nome' => @contact.name.to_s.squish, 'cidade' => data['cidade'].to_s, 'uf' => '', 'contact_id' => @contact.id }
  end

  def bill
    { 'hoje' => data['hoje'], 'acrescimos' => additions, 'consumo_kwh' => kwh.to_f }
  end

  def render(documents)
    renderer = Crm::KitQuote::Renderer.new(store.config)
    return nil unless renderer.available?

    Array(renderer.render(documents)&.dig('arquivos')).presence
  rescue Crm::KitQuote::NoAccess => e
    @render_error = e.message
    nil
  end

  def fail_with(status, motivo)
    Result.new(status: status, motivo: motivo)
  end
end
