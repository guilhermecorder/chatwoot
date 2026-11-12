# Onde o cotador guarda, por conta, a configuração e os acessos aos fornecedores:
# crm_settings.ai_config['kit_quote'].
#
# Token e sessões são SOMENTE ESCRITA: entram pela tela de acessos e nunca voltam
# em resposta nenhuma. A tela só recebe o `status` (tem/não tem, até quando vale).
class Crm::KitQuote::Store
  KEY = 'kit_quote'.freeze
  SESSION_FIELDS = {
    'avt' => %w[accessToken expirationDate urlApi],
    'bluesun' => %w[token expires_at refresh_token refresh_expires_at]
  }.freeze
  REQUIRED = { 'avt' => 'accessToken', 'bluesun' => 'token' }.freeze
  NAMES = { 'avt' => 'AVT', 'bluesun' => 'Bluesun' }.freeze

  def initialize(account)
    @account = account
  end

  def config
    Crm::KitQuote::DEFAULTS.deep_merge(saved['config'] || {})
  end

  def secrets
    saved.slice('avt_token', 'avt_sessao', 'avt_login', 'bluesun_sessao')
  end

  # O que a tela pode saber sobre os acessos (nenhum segredo aqui).
  def status
    {
      'avt' => session_status(saved['avt_sessao'], 'expirationDate').merge(
        'token' => saved['avt_token'].present?, 'id_cliente' => config.dig('avt', 'id_cliente').present?,
        'login' => saved.dig('avt_login', 'senha').present?
      ),
      'bluesun' => session_status(saved['bluesun_sessao'], 'expires_at').merge(
        'renova_ate' => moment(saved.dig('bluesun_sessao', 'refresh_expires_at'))&.iso8601
      )
    }
  end

  # `raw` é o texto que a pessoa copiou no portal (JSON) com o favorito "Copiar sessão".
  def save_session!(supplier, raw)
    raise Crm::KitQuote::Invalid, 'Fornecedor desconhecido.' unless SESSION_FIELDS.key?(supplier)

    data = parse(raw)
    kept = data.slice(*SESSION_FIELDS[supplier]).compact_blank
    if kept[REQUIRED[supplier]].blank?
      raise Crm::KitQuote::Invalid, "Isso não parece a sessão da #{NAMES[supplier]}. Copie de novo no portal, já logado."
    end

    write("#{supplier}_sessao" => kept.merge('salvo_em' => Time.current.iso8601))
  end

  def save_avt_token!(token)
    token = token.to_s.strip
    raise Crm::KitQuote::Invalid, 'Token vazio.' if token.blank? || token.length > 200

    write('avt_token' => token)
  end

  # Usuário e senha do portal da AVT: com eles o servidor entra sozinho quando
  # a sessão vence (o login da AVT não tem verificação de humano).
  def save_avt_login!(email, password)
    email = email.to_s.strip
    raise Crm::KitQuote::Invalid, 'Informe o usuário (e-mail) e a senha do portal da AVT.' if email.blank? || password.to_s.blank?

    write('avt_login' => { 'email' => email, 'senha' => password.to_s })
  end

  def save_avt_client!(client_id)
    id = client_id.to_s.strip
    raise Crm::KitQuote::Invalid, 'O código do cliente na AVT é um número.' unless id.match?(/\A\d{1,10}\z/)

    write('config' => (saved['config'] || {}).deep_merge('avt' => { 'id_cliente' => id.to_i }))
  end

  private

  def saved
    @saved ||= CrmSetting.find_by(account: @account)&.ai_config&.dig(KEY) || {}
  end

  def write(changes)
    Cevico::SettingMerge.merge_key!(@account, :ai_config, KEY) { |current| (current || {}).merge(changes) }
    @saved = nil
    status
  end

  def parse(raw)
    data = raw.is_a?(String) ? JSON.parse(raw.strip) : raw
    raise Crm::KitQuote::Invalid, 'Cole o texto inteiro copiado no portal.' unless data.is_a?(Hash)

    data.to_h.stringify_keys
  rescue JSON::ParserError
    raise Crm::KitQuote::Invalid, 'Cole o texto inteiro copiado no portal.'
  end

  def session_status(session, expiry_field)
    return { 'sessao' => 'sem', 'vence_em' => nil } if session.blank?

    expires = moment(session[expiry_field])
    { 'sessao' => expires&.past? ? 'vencida' : 'ok', 'vence_em' => expires&.iso8601 }
  end

  # Aceita data em texto (AVT) ou em segundos/milissegundos (Bluesun).
  def moment(value)
    return nil if value.blank?
    return Time.zone.at(value > 1e12 ? value / 1000.0 : value) if value.is_a?(Numeric)

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
