# 🔎 O que a tela mostra do Search Console (lê a foto do cache — nunca chama
# o Google). Para cada endereço que apareceu na busca:
#   - descobre qual PÁGINA do sistema ele é (clinica.cevico.com.br/<slug>);
#     o que não é página do sistema (site do WordPress, raiz do hub) entra
#     como "outra página do domínio";
#   - junta, na MESMA janela de 28 dias, o que o sistema mediu dessa página:
#     visitas vindas do Google orgânico → cliques no WhatsApp → leads →
#     agendaram → cirurgias (Cevico::TrafficReport, origem google_organico);
#   - lista os termos buscados que levaram até ela.
# E soma os termos do domínio inteiro (um termo pode cair em mais de uma página).
class Cevico::SearchConsoleReport
  TERMS_ON_PAGE = 12
  TOP_TERMS = 60
  STEPS = %i[views cta leads booked conversions].freeze

  def initialize(account)
    @account = account
    @source = Cevico::SearchConsole.new(account)
  end

  def call
    cache = @source.cache
    base = { configured: @source.configured?, site: @source.site,
             service_account_email: Cevico::GoogleServiceAccount.email(@source.config['service_account_json']) }
    return base.merge(ready: false, error: cache['error']) if cache['window'].blank?

    @cache = cache
    base.merge(ready: true, demo: cache['demo'] == true, fetched_at: cache['fetched_at'], error: cache['error'],
               error_at: cache['error_at'], window: cache['window'], previous_window: cache['previous_window'],
               totals: cache['totals'], daily: cache['daily'] || [], pages: pages, terms: terms)
  end

  private

  def pages
    rows = (@cache['pages'] || []).map { |row| page_row(row) }
    rows.sort_by { |row| [row[:page_id] ? 0 : 1, -row[:impressions]] }
  end

  def page_row(row)
    page = page_for(row['url'])
    out = { url: row['url'], page_id: page&.id, title: page&.title || short_url(row['url']), slug: page&.slug,
            emoji: page&.emoji, clicks: row['clicks'].to_i, impressions: row['impressions'].to_i,
            ctr: row['ctr'].to_f, position: row['position'], previous: row['previous'],
            terms: terms_by_url[row['url']].to_a.first(TERMS_ON_PAGE) }
    out[:site] = system_numbers(page.id) if page
    out
  end

  # termos do domínio inteiro, somados entre as páginas em que caíram
  def terms # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    grouped = (@cache['terms'] || []).group_by { |term| term['query'] }
    list = grouped.map do |query, rows|
      impressions = rows.sum { |r| r['impressions'].to_i }
      clicks = rows.sum { |r| r['clicks'].to_i }
      { query: query, clicks: clicks, impressions: impressions,
        ctr: impressions.positive? ? (clicks.to_f / impressions * 100).round(2) : 0.0,
        position: weighted(rows, 'position'), previous_position: weighted(rows.select { |r| r['previous_position'] }, 'previous_position'),
        urls: rows.sort_by { |r| -r['impressions'].to_i }.map { |r| r['url'] },
        page_ids: rows.filter_map { |r| page_for(r['url'])&.id }.uniq }
    end
    list.sort_by { |term| [-term[:clicks], -term[:impressions]] }.first(TOP_TERMS)
  end

  # posição média ponderada pelas impressões (como o próprio Google faz)
  def weighted(rows, key)
    weight = rows.sum { |r| r['impressions'].to_i }
    return nil if weight.zero?

    (rows.sum { |r| r[key].to_f * r['impressions'].to_i } / weight).round(1)
  end

  def terms_by_url
    @terms_by_url ||= (@cache['terms'] || []).group_by { |term| term['url'] }.transform_values do |list|
      list.sort_by { |t| -t['impressions'].to_i }.map do |t|
        { query: t['query'], clicks: t['clicks'].to_i, impressions: t['impressions'].to_i, ctr: t['ctr'].to_f,
          position: t['position'], previous_position: t['previous_position'] }
      end
    end
  end

  # o que o sistema mediu da página na mesma janela: total e só Google orgânico
  def system_numbers(page_id)
    row = traffic_rows[page_id]
    return { all: blank, organic: blank } if row.nil?

    { all: row.slice(*STEPS), organic: (row.dig(:sources, 'google_organico') || blank).slice(*STEPS) }
  end

  def traffic_rows
    @traffic_rows ||= begin
      since = Date.parse(@cache.dig('window', 'since'))
      finish = Date.parse(@cache.dig('window', 'until'))
      Cevico::TrafficReport.new(@account, since, finish).rows.index_by { |row| row[:page_id] }
    end
  end

  def blank
    STEPS.index_with { 0 }
  end

  # https://clinica.cevico.com.br/lasik-ou-prk(/) ou …/p/lasik-ou-prk → página
  def page_for(url) # rubocop:disable Metrics/CyclomaticComplexity
    @page_for ||= {}
    return @page_for[url] if @page_for.key?(url)

    @page_for[url] = begin
      uri = URI.parse(url.to_s)
      parts = uri.path.to_s.split('/').compact_blank
      parts.shift if parts.first == 'p'
      slug = parts.size == 1 ? parts.first : nil
      slug && public_hosts.include?(uri.host.to_s.downcase) ? pages_by_slug[slug] : nil
    rescue URI::InvalidURIError
      nil
    end
  end

  def public_hosts
    @public_hosts ||= [Cevico::PublicSite.host_for(@account), Cevico::PublicSite.host, Cevico::PublicSite.app_host]
                      .compact_blank.map(&:downcase).uniq
  end

  def pages_by_slug
    @pages_by_slug ||= @account.cevico_pages.select(:id, :title, :slug, :emoji).index_by(&:slug)
  end

  def short_url(url)
    url.to_s.sub(%r{\Ahttps?://}, '').chomp('/')
  end
end
