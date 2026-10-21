# 🔎 GOOGLE SEARCH CONSOLE → cache diário (16/10/2026: "ter controle do
# ranqueamento" das páginas de SEO da clinica.cevico.com.br).
#
# O que o Google conta, por página e por termo buscado: IMPRESSÕES (quantas
# vezes a página apareceu na busca), CLIQUES, CTR (cliques ÷ impressões) e
# POSIÇÃO MÉDIA (1 = primeiro resultado). O sistema já mede o resto do
# caminho (visita → clique no WhatsApp → lead → agendou → cirurgia); juntar
# os dois mostra onde a página perde gente ANTES de chegar no site.
#
# Uma vez por dia (Crm::SearchConsoleSyncJob, ou o botão "Atualizar agora")
# este serviço pergunta à API searchanalytics.query e guarda a foto em
# google_ads_config['search_console_cache'] — a tela só LÊ a foto, nunca
# chama o Google. Janela fixa de 28 dias terminando 3 dias atrás (o Google
# fecha os números com 2–3 dias de atraso) + os 28 dias anteriores para
# comparar. O próprio Search Console guarda 16 meses, então não precisamos
# guardar histórico: se um dia quisermos outra janela, é só perguntar de novo.
#
# Credencial: a MESMA conta de serviço do custo do GA4 (Integrações → Google),
# com o e-mail dela adicionado como usuário da propriedade no Search Console.
# Propriedade padrão: sc-domain:cevico.com.br (domínio inteiro, inclui o site
# do WordPress e a clinica.cevico.com.br).
class Cevico::SearchConsole
  SCOPE = 'https://www.googleapis.com/auth/webmasters.readonly'.freeze
  API = 'https://searchconsole.googleapis.com/webmasters/v3/sites'.freeze
  DEFAULT_SITE = 'sc-domain:cevico.com.br'.freeze
  CACHE_KEY = 'search_console_cache'.freeze
  WINDOW_DAYS = 28
  LAG_DAYS = 3
  # teto do que fica guardado (o crm_settings é uma linha só, lida o tempo todo)
  TERMS_PER_PAGE = 30
  MAX_TERMS = 600
  MAX_PAGES = 300

  def initialize(account)
    @account = account
  end

  def config
    @config ||= CrmSetting.find_by(account: @account)&.google_ads_config || {}
  end

  def site
    config['search_console_site'].presence || DEFAULT_SITE
  end

  def configured?
    config['service_account_json'].present?
  end

  def cache
    config[CACHE_KEY] || {}
  end

  # as duas janelas: a atual (28 dias até 3 dias atrás) e a anterior
  def windows(today = Date.current)
    finish = today - LAG_DAYS
    start = finish - (WINDOW_DAYS - 1)
    { current: [start, finish], previous: [start - WINDOW_DAYS, start - 1] }
  end

  # pergunta tudo ao Google e grava a foto. Devolve { ok: true } ou { error: }
  def sync!
    return { error: 'Conta de serviço do Google não configurada em Integrações → Google.' } unless configured?

    snapshot = fetch_snapshot
    store!(snapshot)
    { ok: true, pages: snapshot['pages'].size, terms: snapshot['terms'].size }
  rescue ApiError => e
    store_error!(e.message)
    { error: e.message }
  rescue StandardError => e
    Rails.logger.error "[Cevico::SearchConsole] conta=#{@account.id} #{e.class}: #{e.message}"
    store_error!('Falha inesperada ao falar com o Google. Tente de novo mais tarde.')
    { error: e.message }
  end

  # teste de Integrações: 1 pergunta pequena, nada gravado
  def test
    return { success: false, error: 'Cole o JSON da conta de serviço primeiro.' } unless configured?

    win = windows[:current]
    rows = query(win, [], row_limit: 1)
    clicks = rows.first&.dig('clicks').to_i
    { success: true, message: "Search Console respondeu: #{clicks} clique(s) do Google nos últimos #{WINDOW_DAYS} dias em #{site}." }
  rescue ApiError => e
    { success: false, error: e.message }
  end

  class ApiError < StandardError; end

  private

  def fetch_snapshot # rubocop:disable Metrics/AbcSize
    cur = windows[:current]
    prev = windows[:previous]
    {
      'site' => site,
      'fetched_at' => Time.current.iso8601,
      'window' => { 'since' => cur[0].iso8601, 'until' => cur[1].iso8601 },
      'previous_window' => { 'since' => prev[0].iso8601, 'until' => prev[1].iso8601 },
      'totals' => { 'current' => metrics(query(cur, []).first), 'previous' => metrics(query(prev, []).first) },
      'pages' => pages(cur, prev),
      'terms' => terms(cur, prev),
      'daily' => query([prev[0], cur[1]], ['date'], row_limit: WINDOW_DAYS * 2).map do |row|
        [row['keys'][0], row['clicks'].to_i, row['impressions'].to_i]
      end
    }
  end

  # por página: números da janela atual + os da anterior
  def pages(cur, prev)
    before = query(prev, ['page'], row_limit: 1000).to_h { |row| [row['keys'][0], metrics(row)] }
    query(cur, ['page'], row_limit: 1000).first(MAX_PAGES).map do |row|
      url = row['keys'][0]
      metrics(row).merge('url' => url, 'previous' => before[url])
    end
  end

  # termos buscados por página (o Google esconde os termos muito raros, então
  # a soma dos termos de uma página fica um pouco abaixo do total dela)
  def terms(cur, prev) # rubocop:disable Metrics/AbcSize
    before = query(prev, %w[page query], row_limit: 5000).to_h { |row| [row['keys'], row['position'].to_f.round(1)] }
    rows = query(cur, %w[page query], row_limit: 5000)
    kept = rows.group_by { |row| row['keys'][0] }
               .flat_map { |_url, list| list.sort_by { |row| -row['impressions'].to_i }.first(TERMS_PER_PAGE) }
               .sort_by { |row| [-row['clicks'].to_i, -row['impressions'].to_i] }
               .first(MAX_TERMS)
    kept.map do |row|
      metrics(row).merge('url' => row['keys'][0], 'query' => row['keys'][1], 'previous_position' => before[row['keys']])
    end
  end

  def metrics(row)
    return { 'clicks' => 0, 'impressions' => 0, 'ctr' => 0.0, 'position' => nil } if row.nil?

    { 'clicks' => row['clicks'].to_i, 'impressions' => row['impressions'].to_i,
      'ctr' => (row['ctr'].to_f * 100).round(2), 'position' => row['position'].to_f.round(1) }
  end

  def query(window, dimensions, row_limit: 1)
    response = HTTParty.post(
      "#{API}/#{ERB::Util.url_encode(site)}/searchAnalytics/query",
      headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' },
      body: { startDate: window[0].iso8601, endDate: window[1].iso8601, dimensions: dimensions, rowLimit: row_limit }.to_json,
      timeout: 30
    )
    raise ApiError, error_message(response) unless response.success?

    response.parsed_response['rows'] || []
  end

  def token
    @token ||= begin
      value, error = Cevico::GoogleServiceAccount.access_token(config['service_account_json'], SCOPE)
      raise ApiError, error if value.blank?

      value
    end
  end

  def error_message(response)
    google = response.parsed_response.is_a?(Hash) ? response.parsed_response.dig('error', 'message') : nil
    case response.code
    when 403
      email = Cevico::GoogleServiceAccount.email(config['service_account_json'])
      "O Google negou acesso a #{site}. Adicione #{email || 'o e-mail da conta de serviço'} como usuário da " \
        'propriedade no Search Console (Configurações → Usuários e permissões) e confira se a API ' \
        '"Google Search Console API" está ativada no Google Cloud.'
    when 404 then "O Google não achou a propriedade #{site}. Confira o nome em Integrações → Google (ex.: sc-domain:cevico.com.br)."
    else "Search Console: #{google.presence || "HTTP #{response.code}"}"
    end
  end

  def store!(snapshot)
    Cevico::SettingMerge.merge_key!(@account, :google_ads_config, CACHE_KEY) { |_old| snapshot }
  end

  # mantém a última foto boa e anota o erro (a tela mostra os dois)
  def store_error!(message)
    Cevico::SettingMerge.merge_key!(@account, :google_ads_config, CACHE_KEY) do |old|
      old.merge('error' => message, 'error_at' => Time.current.iso8601)
    end
  end
end
