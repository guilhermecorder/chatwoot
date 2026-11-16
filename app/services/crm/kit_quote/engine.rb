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
  # margin: true (padrão) = dimensiona para o consumo + a FOLGA de 10% e só deixa kit que produz isso
  # (Guilherme, 16/11/2026); false = "montar na mão" (Crm::KitQuote::Assembly), que pede o consumo exato do kit.
  def run(kwh_month:, grid: 'bifasico', roof: nil, margin: true)
    grid = 'bifasico' unless Crm::KitQuote::GRIDS.include?(grid)
    roof = nil unless Crm::KitQuote::ROOFS.key?(roof)
    target = margin ? Crm::KitQuote.sized_kwh(kwh_month, @config) : kwh_month.to_f
    lines, all = quote_until_covered(target, grid, roof, margin)
    all = covering(all, target) if margin
    summary(kwh_month, target, grid, roof).merge(
      'fornecedores' => lines,
      'opcoes' => Crm::KitQuote::Picker.pick(all, @config['max_opcoes'].to_i),
      'medias' => Crm::KitQuote::Average.by_type(all)
    )
  end

  private

  TRIES = 3 # cotação + no máximo 2 novas pedidas, quando o fornecedor arredonda o kit para baixo
  PUSH = 1.05 # cada nova pedida vai 5% além do que faltou, para o fornecedor passar para a placa de cima
  TYPES = %w[string micro].freeze

  # O fornecedor arredonda as placas e usa o sol dele: pedir o consumo + 10% ainda pode voltar kit que produz menos.
  # Se algum fornecedor/tipo só trouxe kit abaixo, pede de novo com o consumo aumentado na proporção que faltou.
  # As opções de todas as pedidas ficam juntas (o Picker tira as repetidas).
  def quote_until_covered(target, grid, roof, margin)
    ask_kwh = target
    lines = []
    all = []
    before = nil
    TRIES.times do
      lines, options = quote_all(ask_kwh, grid, roof)
      all += options
      ratio = margin && shortfall(all, target)
      break if !ratio || (before && ratio >= before) # cobriu, ou o fornecedor não passa disso

      before = ratio
      ask_kwh = (ask_kwh * ratio * PUSH).round(1)
    end
    [lines, all]
  end

  def quote_all(kwh, grid, roof)
    kwp = Crm::KitQuote.needed_kwp(kwh, @config['incidencia_solar'], @config['perda'])
    answers = Crm::KitQuote.together(suppliers(kwh, kwp, grid, roof).map { |name, query| -> { ask(name, query) } })
    [answers.map(&:first), answers.flat_map(&:last)]
  end

  def by_kind(options)
    options.group_by { |o| o.values_at('fornecedor', 'tipo') }
  end

  def covers?(option, target)
    Crm::KitQuote.production(option['potencia_kwp'], @config) >= target - 1
  end

  # nil = todo tipo que veio tem kit que cobre; senão, quanto falta (> 1) no tipo que ficou mais longe
  def shortfall(options, target)
    ratios = by_kind(options).filter_map do |(_, type), list|
      next unless TYPES.include?(type)
      next if list.any? { |o| covers?(o, target) }

      best = list.map { |o| Crm::KitQuote.production(o['potencia_kwp'], @config) }.max
      target / best if best.positive?
    end
    ratios.max
  end

  # Tira, de cada fornecedor e tipo, os kits que não produzem o consumo + folga — se ali tiver algum que produz.
  def covering(options, target)
    by_kind(options).values.flat_map do |list|
      enough = list.select { |o| covers?(o, target) }
      enough.presence || list
    end
  end

  def summary(kwh_month, target, grid, roof)
    {
      'consumo_kwh_mes' => kwh_month.to_f,
      'consumo_dimensionado' => target.to_f,
      'folga' => kwh_month.to_f.positive? ? ((target / kwh_month.to_f) - 1).round(2) : 0,
      'rede' => grid,
      'telhado' => roof && { 'chave' => roof, 'nome' => Crm::KitQuote::ROOFS[roof] },
      'cidade' => "#{@config['cidade']}/#{@config['uf']}",
      'incidencia_solar' => @config['incidencia_solar'].to_f,
      'perda' => @config['perda'].to_f,
      'potencia_necessaria_kwp' => Crm::KitQuote.needed_kwp(target, @config['incidencia_solar'], @config['perda']).round(2)
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
    avt, bluesun = clients
    {
      'AVT' => -> { avt.quote(kwp, grid) },
      'Bluesun' => -> { bluesun.quote(kwh_month, grid, (@config['perda'].to_f * 100).round, roof) }
    }
  end

  # os portais entram uma vez só, mesmo quando a cotação é pedida de novo
  def clients
    @clients ||= [Crm::KitQuote::Avt, Crm::KitQuote::Bluesun].map do |klass|
      klass.new(@config, @secrets, @store).tap(&:prepare)
    end
  end
end
