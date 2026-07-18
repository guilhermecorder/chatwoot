# Importa dados de cirurgia de uma planilha do Google Sheets.
#
# Como funciona: a planilha precisa estar compartilhada como "qualquer pessoa
# com o link pode ver". O serviço converte o link normal de compartilhamento
# no link de exportação CSV, baixa e interpreta as colunas de forma flexível
# (aceita variações de nome: Data, Nome, Paciente, Procedimento, Valor,
# Unidade...). O resultado fica em cache no crm_settings.sheets_config para o
# Dashboard não precisar baixar a planilha a cada visita.
class Crm::SheetsSurgeryService
  require 'csv'

  CACHE_TTL = 1.hour

  # nomes de coluna aceitos (sem acento, minúsculo) → campo normalizado
  COLUMN_ALIASES = {
    'data' => :date, 'data da cirurgia' => :date, 'dia' => :date,
    'nome' => :name, 'paciente' => :name, 'nome do paciente' => :name,
    'telefone' => :phone, 'celular' => :phone, 'whatsapp' => :phone,
    'procedimento' => :procedure, 'cirurgia' => :procedure, 'tipo' => :procedure,
    'valor' => :value, 'valor (r$)' => :value, 'preco' => :value, 'receita' => :value,
    'unidade' => :unit, 'clinica' => :unit, 'local' => :unit
  }.freeze

  def initialize(account:)
    @account = account
    @settings = CrmSetting.find_or_create_by!(account: account)
  end

  def configured?
    config['sheet_url'].present?
  end

  # baixa a planilha agora e devolve { success:, rows:, headers:, message: }
  def fetch!
    return { success: false, message: 'Nenhuma planilha configurada.' } unless configured?

    csv_url = export_url(config['sheet_url'])
    return { success: false, message: 'Link inválido. Cole o link de compartilhamento do Google Sheets.' } if csv_url.blank?

    response = HTTParty.get(csv_url, timeout: 20, follow_redirects: true)
    unless response.success?
      return { success: false, message: "Google respondeu com status #{response.code}. Confira se a planilha está compartilhada como \"qualquer pessoa com o link\"." }
    end

    rows, headers = parse_csv(response.body.to_s)
    return { success: false, message: 'Não encontrei as colunas esperadas (Data, Nome, Procedimento, Valor, Unidade...).' } if rows.nil?

    cfg = config.merge(
      'cache_rows' => rows,
      'cache_headers' => headers,
      'fetched_at' => Time.current.iso8601
    )
    @settings.update!(sheets_config: cfg)

    { success: true, rows: rows, headers: headers, message: "#{rows.size} linha(s) importada(s) da planilha. ✓" }
  rescue CSV::MalformedCSVError
    { success: false, message: 'O arquivo retornado não é um CSV válido. Confira o link.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::SheetsSurgery] #{e.class}: #{e.message}"
    { success: false, message: "Erro ao baixar a planilha: #{e.message}" }
  end

  # linhas em cache; atualiza sozinho se o cache estiver velho
  def rows
    return [] unless configured?

    fetched_at = config['fetched_at'] && Time.zone.parse(config['fetched_at'])
    fetch! if fetched_at.nil? || fetched_at < CACHE_TTL.ago
    (config_reloaded['cache_rows'] || []).map(&:with_indifferent_access)
  end

  private

  def config
    @settings.sheets_config || {}
  end

  def config_reloaded
    @settings.reload.sheets_config || {}
  end

  # https://docs.google.com/spreadsheets/d/<ID>/edit#gid=0 → export CSV
  def export_url(url)
    match = url.to_s.match(%r{docs\.google\.com/spreadsheets/d/([\w-]+)})
    return nil unless match

    gid = url.to_s[/[#&?]gid=(\d+)/, 1] || '0'
    "https://docs.google.com/spreadsheets/d/#{match[1]}/export?format=csv&gid=#{gid}"
  end

  def parse_csv(body)
    table = CSV.parse(body.force_encoding('UTF-8').scrub, headers: true)
    return [nil, nil] if table.headers.blank?

    mapping = {}
    table.headers.compact.each do |header|
      key = COLUMN_ALIASES[normalize(header)]
      mapping[header] = key if key && !mapping.value?(key)
    end
    # precisa de pelo menos data ou nome para valer
    return [nil, nil] unless mapping.value?(:date) || mapping.value?(:name)

    rows = table.filter_map do |row|
      item = {}
      mapping.each { |header, key| item[key.to_s] = row[header].to_s.strip }
      next if item.values.all?(&:blank?)

      item['date'] = normalize_date(item['date'])
      item['value_number'] = parse_money(item['value'])
      item
    end

    [rows, mapping.keys]
  end

  def normalize(text)
    text.to_s.strip.downcase
        .unicode_normalize(:nfd).gsub(/[\u0300-\u036f]/, '')
  end

  # aceita 13/07/2026, 13/07, 2026-07-13 → devolve ISO (yyyy-mm-dd)
  def normalize_date(raw)
    return nil if raw.blank?
    return raw if raw.match?(/\A\d{4}-\d{2}-\d{2}/)

    if (m = raw.match(%r{\A(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?}))
      year = m[3].presence || Date.current.year.to_s
      year = "20#{year}" if year.length == 2
      format('%04d-%02d-%02d', year.to_i, m[2].to_i, m[1].to_i)
    end
  rescue StandardError
    nil
  end

  # "R$ 5.000,00" / "5000" / "5.000" / "1.234.567" → número correto.
  # BUG antigo: "5.000" (milhar sem centavos) virava 5.0 — receita 1000× menor.
  def parse_money(raw)
    return 0.0 if raw.blank?

    cleaned = raw.gsub(/[^\d,.-]/, '')
    if cleaned.include?(',')
      # padrão BR: vírgula = decimal, ponto = separador de milhar
      cleaned = cleaned.tr('.', '').tr(',', '.')
    elsif cleaned.count('.') > 1 || cleaned.match?(/\.\d{3}(?:\D|\z)/)
      # só pontos em posição de MILHAR ("5.000", "1.234.567") → não é decimal
      cleaned = cleaned.delete('.')
    end
    cleaned.to_f
  end
end
