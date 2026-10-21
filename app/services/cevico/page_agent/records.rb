# 🏆 A MÉDIA DA CASA e o RECORDE de cada taxa entre as nossas páginas (item
# 353) — a mesma régua dos criativos: "vamos buscar sempre superar a média" e
# "o recorde pra gente ir buscar". Recorde = a melhor página dos últimos 90
# dias com volume mínimo. Guardado por 1 hora.
class Cevico::PageAgent::Records
  DAYS = 90
  CACHE_TTL = 1.hour

  def initialize(account:, until_date: Date.current - 1)
    @account = account
    @until_date = until_date
  end

  # { averages: { chave => taxa }, records: { chave => { 'value', 'page_id', 'page_title', 'emoji', 'since', 'until' } } }
  def call
    Rails.cache.fetch("cevico/page_agent/records/#{@account.id}/#{@until_date.iso8601}", expires_in: CACHE_TTL) { compute }
  end

  private

  def compute # rubocop:disable Metrics/AbcSize
    since = @until_date - (DAYS - 1)
    report = Cevico::TrafficReport.new(@account, since, @until_date)
    rows = report.rows.select { |r| r[:page_id] }
    gsc = search_console
    averages = Cevico::PageAgent::Rates.for(Cevico::PageAgent::Rates.sum(rows), gsc_totals(gsc))
    records = {}
    rows.each do |row|
      rates = Cevico::PageAgent::Rates.for(row, gsc[row[:page_id]])
      rates.each do |key, value|
        next if value.nil? || (records[key] && records[key]['value'] >= value)

        records[key] = { 'value' => value, 'page_id' => row[:page_id], 'page_title' => row[:title], 'emoji' => row[:emoji],
                         'since' => since.iso8601, 'until' => @until_date.iso8601 }
      end
    end
    { averages: averages, records: records, since: since.iso8601, until: @until_date.iso8601 }
  end

  # { page_id => linha do Search Console } (28 dias, foto diária) — vazio sem o Google ligado
  def search_console
    data = Cevico::SearchConsoleReport.new(@account).call
    return {} unless data.is_a?(Hash) && data[:ready]

    Array(data[:pages]).select { |p| p[:page_id] }.index_by { |p| p[:page_id] }
  rescue StandardError
    {}
  end

  def gsc_totals(gsc)
    return nil if gsc.empty?

    impressions = gsc.values.sum { |p| p[:impressions].to_i }
    clicks = gsc.values.sum { |p| p[:clicks].to_i }
    { impressions: impressions, ctr: impressions.positive? ? (clicks.to_f / impressions * 100) : 0 }
  end
end
