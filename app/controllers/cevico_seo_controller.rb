# 🗺️ CEVICO item 355: mapa do site (sitemap.xml) e robots.txt do domínio
# das páginas (ex.: clinica.cevico.com.br) — o Google acha as páginas novas
# sozinho, sem esperar alguém linkar.
#
# - /sitemap.xml: só no domínio oficial das páginas. Lista as páginas
#   PUBLICADAS cujo endereço oficial é ESTE domínio (rodada 334: cada empresa
#   no seu), menos as variações de anúncio (-g, -m, -gd e qualquer página com
#   <meta name="robots" content="noindex">), que não devem ir pro Google.
# - /robots.txt: no domínio das páginas libera tudo e aponta o sitemap; no
#   host do sistema continua o de sempre (era o public/robots.txt, que o
#   servidor entregava antes de qualquer rota — por isso virou rota).
# - /biblioteca/numeros.json: números por página (acessos, cliques, leads,
#   agendou) para a Biblioteca de guias. A chave é o próprio endereço dela:
#   só responde para uma página PUBLICADA deste domínio com o marcador
#   data-biblioteca="1" no HTML. Só contagens — nenhum dado de pessoa.
class CevicoSeoController < ActionController::Base # rubocop:disable Rails/ApplicationController
  include Crm::ResolvesPeriod

  layout false

  # variações de anúncio (Google, Meta, Google Demand Gen) — fora do orgânico
  AD_VARIANT_SLUG = /-(g|m|gd)\z/
  META_TAG = /<meta\b[^>]*>/i
  ROBOTS_META = /\bname\s*=\s*["']?(robots|googlebot)\b/i
  LIBRARY_MARK = /data-biblioteca\s*=\s*["']?1\b/
  LIBRARY_DAYS = [7, 30, 90, 365].freeze
  LIBRARY_PRESETS = %w[today yesterday last7 last_week month last_month last90 year custom].freeze
  LIBRARY_MAX_DAYS = 731 # personalizado: no máximo 2 anos

  def sitemap
    xml = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |doc|
      doc.urlset(xmlns: 'http://www.sitemaps.org/schemas/sitemap/0.9') do
        sitemap_entries.each do |loc, lastmod|
          doc.url do
            doc.loc loc
            doc.lastmod lastmod.utc.iso8601 if lastmod
          end
        end
      end
    end

    expires_in 15.minutes, public: true
    render xml: xml.to_xml
  end

  def robots
    expires_in 1.hour, public: true
    render plain: robots_text, content_type: 'text/plain'
  end

  def library_numbers
    library = library_page
    return head :not_found if library.nil?

    since_date, until_date, preset = library_period
    key = "cevico:biblioteca:#{library.account_id}:#{since_date}:#{until_date}"
    numbers = Rails.cache.fetch(key, expires_in: 10.minutes) do
      library_payload(library.account, since_date, until_date)
    end

    expires_in 5.minutes, public: false
    render json: numbers.merge(preset: preset)
  end

  private

  # a Biblioteca pedida no ?de=: publicada, deste domínio e com o marcador
  def library_page
    slug = params[:de].to_s
    return nil if slug.blank?

    page = CevicoPage.published.includes(:account).find_by(slug: slug)
    return nil if page.nil? || !Cevico::PublicSite.host_for(page.account).to_s.casecmp?(request.host)

    page.custom_html.to_s.match?(LIBRARY_MARK) ? page : nil
  end

  # 22/10: a Biblioteca usa a RÉGUA PADRÃO do sistema (item 321 — Hoje, Ontem,
  # 7 dias, Semana passada, Este mês, Mês passado, 90 dias, Este ano,
  # Personalizado) via ?preset= (+ from/to no personalizado). Sem preset,
  # continua o ?dias= antigo (7/30/90/365) — a versão publicada não quebra.
  def library_period
    range = LIBRARY_PRESETS.include?(params[:preset]) ? standard_period_range : nil
    return library_preset_dates(range) if range

    days = LIBRARY_DAYS.include?(params[:dias].to_i) ? params[:dias].to_i : 30
    [Date.current - (days - 1), Date.current, 'dias']
  end

  # nunca no futuro e no máximo 2 anos (personalizado com De muito antigo)
  def library_preset_dates(range)
    until_date = [range.last.to_date, PERIOD_TZ.today].min
    since_date = [range.first.to_date, until_date - (LIBRARY_MAX_DAYS - 1)].max
    [since_date, until_date, params[:preset]]
  end

  # contagens por página no período (sem a linha do hub) + o total
  def library_payload(account, since_date, until_date)
    pages = Cevico::TrafficReport.new(account, since_date, until_date).rows.select { |row| row[:slug].present? }
    numbers = pages.to_h do |row|
      [row[:slug], { acessos: row[:views], cliques: row[:cta], leads: row[:leads], agendou: row[:booked] }]
    end
    total = %i[acessos cliques leads agendou].index_with { |key| numbers.values.sum { |n| n[key] } }
    { since: since_date.iso8601, until: until_date.iso8601, dias: (until_date - since_date).to_i + 1,
      atualizado: Time.current.iso8601, paginas: numbers, total: total }
  end

  def robots_text
    unless Cevico::PublicSite.official_host?(request.host)
      return "# See http://www.robotstxt.org/robotstxt.html for documentation on how to use the robots.txt file\n" \
             "#\n\nUser-agent: *\nDisallow: /widget\n"
    end

    "User-agent: *\nAllow: /\nDisallow: /widget\n\nSitemap: https://#{request.host}/sitemap.xml\n"
  end

  # [endereço, última mudança] — a raiz (hub) primeiro, quando o domínio é das páginas
  def sitemap_entries
    pages = indexable_pages
    entries = pages.map { |page| [Cevico::PublicSite.page_url(page.slug, account: page.account), page.updated_at] }
    return entries unless Cevico::PublicSite.public_root?(request.host)

    [["https://#{request.host}/", pages.map(&:updated_at).max]] + entries
  end

  # páginas publicadas que moram NESTE domínio e podem ir pro Google
  def indexable_pages
    hosts = {}
    CevicoPage.published.includes(:account).order(:slug).select do |page|
      page_host = hosts[page.account_id] ||= Cevico::PublicSite.host_for(page.account).to_s
      page_host.casecmp?(request.host) && !noindex?(page)
    end
  end

  def noindex?(page)
    return true if page.slug.match?(AD_VARIANT_SLUG)

    page.custom_html.to_s.scan(META_TAG).any? { |tag| tag.match?(ROBOTS_META) && tag.match?(/noindex/i) }
  end
end
