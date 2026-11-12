# AVT (portal.avtenergy.com.br, plataforma Solaryum).
#
# Dois caminhos:
# 1. API oficial — GET /integracaoPlataforma/MontarKits com o "Token de Plataformas".
#    Em 11/11/2026 o token foi gerado, mas a API respondeu "Acesso negado!!!":
#    falta a AVT liberar. Quando liberar, este caminho passa a funcionar sozinho.
# 2. Sessão do portal — POST /api/Pedido/BuscarCombinacoes, a mesma consulta
#    que a tela "Monte Seu Kit" faz.
class Crm::KitQuote::Avt
  TYPES = { 0 => 'string', 1 => 'micro', 2 => 'hibrido' }.freeze
  PHASE = { 'monofasico' => 0, 'bifasico' => 0, 'trifasico' => 2 }.freeze # o portal não oferece bifásico
  EXPIRED = 'AVT: a sessão do portal venceu. Ligue de novo em Acessos dos fornecedores.'.freeze
  NO_SESSION = 'AVT: sem sessão do portal. Ligue em Acessos dos fornecedores.'.freeze
  STRING_THEN_MICRO = [false, true].freeze
  # A consulta de kits do portal só responde se disser que vem do portal
  # (sem isso: 400 "Acesso Negado!!!", visto em 11/11/2026).
  PORTAL = { 'Origin' => 'https://portal.avtenergy.com.br', 'Referer' => 'https://portal.avtenergy.com.br/' }.freeze
  NO_CLIENT = 'AVT: falta o código do cliente na AVT (id_cliente) na configuração.'.freeze

  # secrets: { 'avt_token' => '...', 'avt_sessao' => { 'accessToken', 'expirationDate', 'urlApi' } }
  # store (opcional): Crm::KitQuote::Store, para guardar a sessão nova depois do login automático
  def initialize(config, secrets, store = nil)
    @config = config
    @avt = config['avt']
    @secrets = secrets || {}
    @store = store
  end

  # Chamar ANTES das consultas em paralelo: se a sessão do portal não existe ou
  # venceu e há usuário e senha guardados, entra sozinho. Grava no banco, por
  # isso roda na linha principal e não dentro das consultas simultâneas.
  def prepare
    stored = @secrets['avt_sessao']
    return unless auto_login? && (stored.blank? || stored['accessToken'].blank? || expired?(stored['expirationDate']))

    @secrets = @secrets.merge('avt_sessao' => login!)
  rescue Crm::KitQuote::NoAccess => e
    @login_error = e.message
  end

  # Devolve [opções, caminho usado]. Tenta a API oficial; se a AVT ainda não
  # liberou, cai para a sessão do portal.
  def quote(kwp, grid)
    @kwp = kwp
    @grid = grid
    [official, 'API oficial']
  rescue Crm::KitQuote::NoAccess => e
    begin
      [session, 'sessão do portal']
    rescue Crm::KitQuote::NoAccess => e2
      raise Crm::KitQuote::NoAccess, "#{e.message} #{e2.message}"
    end
  end

  private

  # ---------- 1. API oficial ----------

  def official
    token = @secrets['avt_token'].to_s
    raise Crm::KitQuote::NoAccess, 'AVT: sem token de plataformas.' if token.blank?

    [0, 1].flat_map do |inverter_type|
      official_kits(token, inverter_type).map { |kit| official_option(kit, inverter_type) }
    end
  end

  def official_kits(token, inverter_type)
    status, data = Crm::KitQuote::Http.get(
      "#{@avt['base']}/integracaoPlataforma/MontarKits",
      params: { token: token, potenciaDoKit: @kwp.round(2), tensao: 1, fase: PHASE.fetch(@grid, 0),
                tipoInv: inverter_type, ibge: @config['ibge'] }
    )
    return data if status == 200 && data.is_a?(Array)
    return Array(data['kits'] || data['data']) if status == 200 && data.is_a?(Hash)

    raise Crm::KitQuote::NoAccess, "AVT ainda não liberou o token (resposta: #{data.to_s.first(60)})"
  end

  def official_option(kit, inverter_type)
    parts = Array(kit['composicao'])
    panel = parts.find { |c| c['categoria'].to_s.downcase.match?(/painel|modul/) }
    inverter = parts.find { |c| c['categoria'].to_s.downcase.include?('inversor') }
    Crm::KitQuote.option(
      supplier: 'AVT', type: TYPES[inverter_type], kwp: kit['potencia'].presence || @kwp,
      panels: panel ? "#{panel['qtd'].to_i} × #{panel['descricao']}" : kit['marcaPainel'], panel_count: panel && panel['qtd'],
      inverter: inverter ? inverter['descricao'] : kit['marcaInversor'],
      price: kit['precoVenda']
    )
  end

  # ---------- 2. Sessão do portal ----------

  def session
    open_session!
    jobs = panels.flat_map do |panel|
      qty = Crm::KitQuote.panels_for(@kwp, panel['potencia'])
      total = (qty * panel['potencia'].to_f / 1000).round(2)
      STRING_THEN_MICRO.map { |micro| -> { combinations(panel, qty, total, micro) } }
    end
    @refused = Queue.new
    options = Crm::KitQuote.together(jobs).flatten
    # nenhuma opção e o portal recusou alguma consulta: é falta de acesso, não "zero kits"
    raise Crm::KitQuote::NoAccess, "AVT: o portal recusou a consulta de kits (#{@refused.pop})." if options.empty? && !@refused.empty?

    options
  end

  def open_session!
    stored = @secrets['avt_sessao']
    raise Crm::KitQuote::NoAccess, @login_error if @login_error
    raise Crm::KitQuote::NoAccess, NO_SESSION if stored.blank? || stored['accessToken'].blank?
    raise Crm::KitQuote::NoAccess, EXPIRED if expired?(stored['expirationDate'])
    raise Crm::KitQuote::NoAccess, NO_CLIENT if @avt['id_cliente'].blank?

    @base = (stored['urlApi'].presence || @avt['base']).to_s.chomp('/')
    @auth = PORTAL.merge('Authorization' => "Bearer #{stored['accessToken']}")
  end

  def auto_login?
    @secrets.dig('avt_login', 'senha').present?
  end

  # Entra no portal com o usuário e a senha guardados e devolve a sessão nova.
  def login!
    base = @avt['base'].to_s.chomp('/')
    credentials = @secrets['avt_login'].slice('email', 'senha')
    status, data = Crm::KitQuote::Http.post("#{base}/api/v2/account/login", headers: PORTAL, body: credentials)
    unless status == 200 && data.is_a?(Hash) && data['accessToken'].present?
      raise Crm::KitQuote::NoAccess, "AVT: o portal não aceitou o usuário e a senha guardados [#{status}]. Confira em Acessos dos fornecedores."
    end

    session = data.slice('accessToken', 'expirationDate').merge('urlApi' => base)
    @store&.save_session!('avt', session)
    session
  end

  def panels
    status, list = Crm::KitQuote::Http.get("#{@base}/api/Produto/BuscarPaineis",
                                           params: { idFornecedor: @avt['id_fornecedor'] }, headers: @auth)
    raise Crm::KitQuote::NoAccess, EXPIRED if status == 401
    raise Crm::KitQuote::NoAccess, "AVT: não consegui listar os painéis [#{status}]" unless status == 200 && list.is_a?(Array)

    list.select { |p| p['potencia'].to_f.positive? }
  end

  def combinations(panel, qty, total, micro)
    status, kits = Crm::KitQuote::Http.post("#{@base}/api/Pedido/BuscarCombinacoes",
                                            body: session_body(panel, qty, total, micro), headers: @auth)
    unless status == 200 && kits.is_a?(Array)
      @refused << "#{kits.to_s.first(40)} [#{status}]"
      return []
    end

    note = @grid == 'bifasico' ? 'rede bifásica cotada como monofásica 220 V' : ''
    kits.map do |kit|
      Crm::KitQuote.option(
        supplier: 'AVT', type: TYPES.fetch(kit['tipoInv'], micro ? 'micro' : 'string'), kwp: total,
        panels: "#{qty} × #{panel['descricao']}", panel_count: qty, inverter: kit['inversor'],
        price: kit['valorFinal'].presence || kit['valorTotal'], note: note
      )
    end
  end

  def session_body(panel, qty, total, micro)
    {
      fase: PHASE.fetch(@grid, 0), idPainel: panel['idProduto'], qtdPainel: qty, tensao: 1, fileiras: [],
      idMarca: nil, idFornecedorPainel: @avt['id_fornecedor'], buscarMicroinversores: micro,
      potenciaTotal: total, idCliente: @avt['id_cliente'], percentual: @avt['percentual'], valorDa: 0,
      ibge: @config['ibge'], uf: @config['uf'], incluirStringBox: true, tipoInv: 0, idMarcaStringbox: nil
    }
  end

  def expired?(value)
    return false if value.blank?

    Time.zone.parse(value.to_s)&.past? || false
  rescue ArgumentError
    false
  end
end
