# Bluesun (orcamentos.bluesundobrasil.com.br).
#
# Ainda sem acesso oficial para a LIFE. Usa a sessão do portal: alguém entra no
# site (o login tem verificação de humano), copia a sessão, cola na tela do
# gerador e o sistema reaproveita. A sessão vale 3 h e a chave de renovação vale
# 7 dias: quando a sessão vence, o servidor renova sozinho (POST /v1/validar_token
# com { refresh_token }, igual ao portal). Um login humano por semana.
#
# Consulta: POST /v1/orcamentos/geracao/simulacao — aceita o consumo da conta
# direto e devolve os kits com preço, frete e lista de itens. Com o tipo de
# telhado, a cotação já vem COM a estrutura (incluir_estrutura +
# id_tipo_estrutura_telhado, ids em config['bluesun']['estruturas']).
class Crm::KitQuote::Bluesun
  TYPES = { 'inversor_ongrid' => 'string', 'micro_inversor_ongrid' => 'micro', 'inversor_hibrido' => 'hibrido' }.freeze
  LOGIN_AGAIN = 'Ligue de novo em Acessos dos fornecedores.'.freeze

  # Renova quando faltar menos que isso para a sessão vencer.
  RENEW_MARGIN = 120

  # secrets: { 'bluesun_sessao' => { 'token', 'expires_at', 'refresh_token', 'refresh_expires_at' } }
  # store (opcional): Crm::KitQuote::Store, para guardar a sessão renovada
  def initialize(config, secrets, store = nil)
    @config = config
    @bluesun = config['bluesun']
    @secrets = secrets || {}
    @store = store
  end

  # Chamar ANTES das consultas em paralelo (grava no banco): se a sessão de 3 h
  # venceu e a chave de renovação ainda vale, renova como o portal faz sozinho.
  # margin: o robô de hora em hora (Crm::KitQuoteKeepaliveJob) renova antes de
  # vencer, para a sessão nunca cair entre uma rodada e outra.
  def prepare(margin: RENEW_MARGIN)
    session = @secrets['bluesun_sessao']
    return unless renewable?(session, margin)

    fresh = renew(session['refresh_token'])
    return if fresh.blank?

    @store&.save_session!('bluesun', fresh)
    @secrets = @secrets.merge('bluesun_sessao' => fresh)
  rescue Crm::KitQuote::NoAccess, Crm::KitQuote::Invalid
    nil # sem renovar, a consulta explica que a sessão venceu
  end

  # Devolve [opções, caminho usado]. roof: chave de Crm::KitQuote::ROOFS (nil = sem estrutura).
  def quote(kwh_month, grid, loss_percent, roof = nil)
    @auth = { 'Authorization' => "Bearer #{session_token}" }
    @structure = @bluesun['estruturas']&.dig(roof.to_s)
    body = body(kwh_month, grid, loss_percent, insurance_id)
    status, data = Crm::KitQuote::Http.post("#{@bluesun['api']}/v1/orcamentos/geracao/simulacao",
                                            body: body, headers: @auth, timeout: 90)
    refuse!(status)
    raise Crm::KitQuote::NoAccess, "Bluesun: a simulação não voltou [#{status}] #{data.to_s.first(60)}" unless status == 200 && data.is_a?(Hash)

    [Array(data['data']).map { |kit| to_option(kit) }, 'sessão do portal']
  end

  private

  def refuse!(status)
    return unless [401, 403].include?(status)

    raise Crm::KitQuote::NoAccess, "Bluesun: o portal não aceitou a sessão [#{status}]. #{LOGIN_AGAIN}"
  end

  def session_token
    session = @secrets['bluesun_sessao']
    raise Crm::KitQuote::NoAccess, 'Bluesun: sem sessão do portal. Ligue em Acessos dos fornecedores.' if session.blank? || session['token'].blank?

    # prepare já tentou renovar; se ainda está vencida, a chave de 7 dias caiu
    raise Crm::KitQuote::NoAccess, "Bluesun: a sessão de 3 h venceu. #{LOGIN_AGAIN}" if expired?(session['expires_at'])

    session['token']
  end

  def expired?(value, margin = 0)
    expires = value.to_f
    expires /= 1000 if expires > 1e12
    expires.positive? && expires < Time.now.to_f + margin
  end

  # A sessão venceu (ou vence já) e a chave de renovação ainda vale.
  def renewable?(session, margin = RENEW_MARGIN)
    return false if session.blank? || session['refresh_token'].blank?

    expired?(session['expires_at'], margin) && !expired?(session['refresh_expires_at'])
  end

  def renew(refresh_token)
    status, data = Crm::KitQuote::Http.post("#{@bluesun['api']}/v1/validar_token", body: { refresh_token: refresh_token })
    return nil unless status == 200 && data.is_a?(Hash) && data['token'].present?

    data.slice('token', 'expires_at', 'refresh_token', 'refresh_expires_at')
  end

  def insurance_id
    status, data = Crm::KitQuote::Http.get("#{@bluesun['api']}/v1/orcamentos/geracao/servicos/seguro_engenharia", headers: @auth)
    refuse!(status)
    list = data.is_a?(Hash) ? data['data'] : data
    first = Array(list).first
    first['id'] if first.is_a?(Hash)
  end

  def body(kwh_month, grid, loss_percent, insurance)
    {
      uf_calculo: @config['uf'], id_empresa: @bluesun['id_empresa'], calcular_por: 'consumo_medio',
      seguro: '1', descarregamento: '0', espessura_cabo: '4', incluir_kit_cabo_extensor: '0',
      id_municipio: @bluesun['id_municipio'], area_rural: false, id_marca_stringboxcc: 0, id_marca_stringboxca: 0,
      tipo_contrato: grid, tensao: '220', autotrafo: '1',
      tipo_inversor: %w[inversor_ongrid micro_inversor_ongrid], todos_modelos_inversores: true, lista_inversores: [],
      incluir_estrutura: @structure ? 1 : 0, incluir_estrutura_secundaria: 0, id_tipo_estrutura_telhado: @structure,
      id_tipo_estrutura_telhado_secundaria: nil, quantidade_painel_estrutura_telhado_secundaria: nil,
      valor_perda: loss_percent.to_i, consumo_medio: kwh_month.to_f.round, margem_mao_de_obra: nil,
      seguro_engenharia: insurance
    }
  end

  def to_option(kit)
    items = Array(kit['lista_itens'])
    Crm::KitQuote.option(
      supplier: 'Bluesun', type: TYPES.fetch(kit['tipo_inversor'], 'string'), kwp: kit['potencia_total_sistema'],
      panels: panels_text(kit, items), panel_count: kit['quantidade_painel'], inverter: inverter_text(kit, items),
      price: kit['valor_final'].presence || kit['valor_original'],
      freight: kit.dig('frete', 'valor_cobrado'), structure: @structure.present?, equipment: equipment(kit),
      note: kit['seguro'] ? 'inclui seguro' : ''
    )
  end

  # Marca e potência separadas, para a proposta não depender do texto do fornecedor.
  def equipment(kit)
    {
      'placa' => { 'quantidade' => kit['quantidade_painel'].to_i, 'marca' => kit.dig('modulo', 'descricao_marca'),
                   'potencia_w' => kit['potencia_painel'] },
      'inversores' => Array(kit['lista_inversores']).map do |i|
        { 'quantidade' => (i['quantidade_total'] || i['qtde'] || 1).to_i, 'marca' => i['descricao_marca'], 'potencia_kw' => i['potencia'] }
      end,
      'peso_kg' => kit['peso'], 'estrutura' => kit['descricao_estrutura_telhado']
    }
  end

  def panels_text(kit, items)
    panel = items.find { |i| i['categoria'].to_s.casecmp('painel').zero? }
    "#{kit['quantidade_painel']} × #{panel ? panel['descricao'] : "#{kit['potencia_painel']} W"}"
  end

  def inverter_text(kit, items)
    inverter = items.find { |i| i['categoria'].to_s.downcase.include?('inversor') }
    return kit['descricao_tipo_inversor'] unless inverter

    "#{(inverter['quantidade_total'] || inverter['qtde'] || 1).to_i} × #{inverter['descricao']}"
  end
end
