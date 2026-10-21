# 💵 Cotação do DÓLAR do dia (item 318, 03/10/2026) — PTAX de venda do
# Banco Central (API pública Olinda, sem chave). Usada para passar o gasto da
# IA (gravado em US$) para reais no ambiente Financeiro & CAC.
#   rates_for(from, to) → { Date => taxa } para TODOS os dias do intervalo:
#   fim de semana/feriado herda o último dia útil anterior.
# Sem resposta do BC → última cotação guardada (até 30 dias) → nil (a tela
# avisa e pede a taxa manual).
class Crm::UsdRateService
  URL = 'https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/' \
        'CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)'.freeze
  LAST_KEY = 'cevico:usd_rate:last'.freeze
  LOOKBACK_DAYS = 10 # pega a sexta quando o período começa num sábado/feriado

  def self.rates_for(from, to)
    new(from, to).rates
  end

  # última cotação conhecida { date:, rate: } (para o rodapé da tela)
  def self.last_known
    Rails.cache.read(LAST_KEY)
  end

  def initialize(from, to)
    @from = from.to_date
    @to = [to.to_date, Time.zone.today].min
    @to = @from if @to < @from
  end

  def rates
    quotes = fetch_quotes
    return fallback_rates if quotes.empty?

    remember(quotes)
    fill(quotes)
  end

  private

  def fetch_quotes
    Rails.cache.fetch(['cevico:usd_rate', @from.iso8601, @to.iso8601], expires_in: 6.hours, skip_nil: true) do
      response = HTTParty.get(URL, query: query, timeout: 10)
      next nil unless response.success?

      parse(response.parsed_response).presence
    end || {}
  rescue StandardError => e
    Rails.logger.warn "[Crm::UsdRateService] #{e.class}: #{e.message}"
    {}
  end

  def query
    {
      '@dataInicial' => "'#{(@from - LOOKBACK_DAYS).strftime('%m-%d-%Y')}'",
      '@dataFinalCotacao' => "'#{@to.strftime('%m-%d-%Y')}'",
      '$format' => 'json',
      '$select' => 'cotacaoVenda,dataHoraCotacao'
    }
  end

  # o BC devolve várias linhas no mesmo dia em alguns casos: fica a última
  def parse(body)
    body = JSON.parse(body) if body.is_a?(String)
    Array(body['value']).each_with_object({}) do |row, acc|
      date = Date.parse(row['dataHoraCotacao'].to_s) rescue nil # rubocop:disable Style/RescueModifier
      acc[date.iso8601] = row['cotacaoVenda'].to_f if date && row['cotacaoVenda'].to_f.positive?
    end
  end

  # todos os dias do período, com o último dia útil para fim de semana/feriado
  def fill(quotes)
    known = quotes.transform_keys { |d| Date.parse(d) }.sort.to_h
    last = known.select { |d, _| d < @from }.values.last || known.values.first
    (@from..@to).index_with do |day|
      last = known[day] if known.key?(day)
      last
    end
  end

  def remember(quotes)
    date, rate = quotes.max_by { |d, _| d }
    Rails.cache.write(LAST_KEY, { date: date, rate: rate }, expires_in: 30.days)
  end

  def fallback_rates
    last = self.class.last_known
    return {} if last.blank?

    (@from..@to).index_with { last[:rate].to_f }
  end
end
