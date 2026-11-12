# Do consumo até as opções: calcula a potência, consulta cada fornecedor e
# escolhe. Um fornecedor sem acesso não derruba os outros: o motivo volta em
# 'fornecedores' para a tela mostrar.
class Crm::KitQuote::Engine
  # config: Hash no formato de Crm::KitQuote::DEFAULTS (já mesclado)
  # secrets: { 'avt_token', 'avt_sessao', 'bluesun_sessao' }
  # store (opcional): onde o login automático da AVT guarda a sessão nova
  def initialize(config, secrets, store = nil)
    @config = config
    @secrets = secrets || {}
    @store = store
  end

  # roof: chave de Crm::KitQuote::ROOFS. Com o telhado, a cotação pede a estrutura junto;
  # sem ele (ou num telhado que o fornecedor ainda não tem mapeado) a cotação fica incompleta
  # e não entra no preço médio do kit.
  def run(kwh_month:, grid: 'bifasico', roof: nil)
    grid = 'bifasico' unless Crm::KitQuote::GRIDS.include?(grid)
    roof = nil unless Crm::KitQuote::ROOFS.key?(roof)
    kwp = Crm::KitQuote.needed_kwp(kwh_month, @config['incidencia_solar'], @config['perda'])
    answers = Crm::KitQuote.together(suppliers(kwh_month, kwp, grid, roof).map { |name, query| -> { ask(name, query) } })
    all = answers.flat_map(&:last)
    summary(kwh_month, grid, roof, kwp).merge(
      'fornecedores' => answers.map(&:first),
      'opcoes' => Crm::KitQuote::Picker.pick(all, @config['max_opcoes'].to_i),
      'medias' => Crm::KitQuote::Average.by_type(all)
    )
  end

  private

  def summary(kwh_month, grid, roof, kwp)
    {
      'consumo_kwh_mes' => kwh_month.to_f,
      'rede' => grid,
      'telhado' => roof && { 'chave' => roof, 'nome' => Crm::KitQuote::ROOFS[roof] },
      'cidade' => "#{@config['cidade']}/#{@config['uf']}",
      'incidencia_solar' => @config['incidencia_solar'].to_f,
      'perda' => @config['perda'].to_f,
      'potencia_necessaria_kwp' => kwp.round(2)
    }
  end

  # Devolve [linha do relatório, opções]. Fornecedor sem acesso vira motivo, não erro.
  def ask(name, query)
    options, path = query.call
    complete = options.count { |o| o['completa'] }
    line = { 'fornecedor' => name, 'ok' => true, 'caminho' => path, 'opcoes' => options.size, 'completas' => complete }
    line['falta'] = options.first['falta'] if complete.zero? && options.any?
    [line, options]
  rescue Crm::KitQuote::NoAccess => e
    [{ 'fornecedor' => name, 'ok' => false, 'motivo' => e.message }, []]
  end

  def suppliers(kwh_month, kwp, grid, roof)
    avt = Crm::KitQuote::Avt.new(@config, @secrets, @store)
    avt.prepare
    bluesun = Crm::KitQuote::Bluesun.new(@config, @secrets, @store)
    bluesun.prepare
    {
      'AVT' => -> { avt.quote(kwp, grid) },
      'Bluesun' => -> { bluesun.quote(kwh_month, grid, (@config['perda'].to_f * 100).round, roof) }
    }
  end
end
