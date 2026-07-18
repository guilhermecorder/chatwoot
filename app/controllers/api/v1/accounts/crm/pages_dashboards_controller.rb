# Análise de Páginas (PÁGINAS PRO, só admin): estatísticas completas por
# página (série diária de visitas/cliques, origem do funil, profundidade
# de leitura, resultados do teste A/B) + o mapa dos FUNIS montados
# (página → página → WhatsApp) com a conversão de cada elo.
class Api::V1::Accounts::Crm::PagesDashboardsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:pages) }

  SERIES_DAYS = 30

  def show
    pages = Current.account.cevico_pages.order(:category, :title).to_a
    render json: {
      pages: pages.map { |p| analytics_json(p) },
      funnels: funnels_json(pages)
    }
  end

  private


  def analytics_json(page) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    stats = page.daily_stats || {}
    series = (0...SERIES_DAYS).map do |i|
      date = Date.current - (SERIES_DAYS - 1 - i)
      day = stats[date.iso8601] || {}
      { date: date.iso8601, view: day['view'].to_i, cta: day['cta'].to_i, next: day['next'].to_i }
    end
    {
      id: page.id,
      title: page.title,
      slug: page.slug,
      status: page.status,
      category: page.category,
      emoji: page.emoji,
      views_count: page.views_count,
      cta_clicks_count: page.cta_clicks_count,
      next_clicks_count: page.next_clicks_count,
      click_rate: rate(page.cta_clicks_count + page.next_clicks_count, page.views_count),
      next_page_id: page.next_page_id,
      cta_url: page.cta_url,
      series: series,
      origins: sum_nested(stats, 'de'),
      scroll: sum_nested(stats, 'scroll'),
      ab_running: page.ab_test_running?,
      ab_variants: page.ab_variants || [],
      ab_results: page.ab_results
    }
  end

  # soma um mapa aninhado do daily_stats em todas as datas ({slug=>n} / {bucket=>n})
  def sum_nested(stats, key)
    totals = Hash.new(0)
    stats.each_value do |day|
      (day[key] || {}).each { |k, v| totals[k] += v.to_i }
    end
    totals.sort_by { |_k, v| -v }.to_h
  end

  # ── Funis: cadeias de next_page_id com a conversão de cada elo ──
  # Elo A→B: cliques no "próximo passo" de A, visitas de B vindas de A
  # (?de=A) e conversões de B (cliques no convite). Fim da cadeia = convite.
  def funnels_json(pages) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    by_id = pages.index_by(&:id)
    target_ids = pages.filter_map(&:next_page_id).uniq
    # cabeça de funil: aponta pra alguém e ninguém aponta pra ela
    heads = pages.select { |p| p.next_page_id.present? && target_ids.exclude?(p.id) }

    heads.map do |head|
      chain = []
      current = head
      seen = []
      while current && seen.exclude?(current.id)
        seen << current.id
        nxt = current.next_page_id && by_id[current.next_page_id]
        origins = sum_nested(current.daily_stats || {}, 'de')
        chain << {
          id: current.id,
          title: current.title,
          slug: current.slug,
          status: current.status,
          emoji: current.emoji,
          views: current.views_count,
          views_from_previous: chain.any? ? origins[chain.last[:slug]].to_i : nil,
          next_clicks: current.next_clicks_count,
          cta_clicks: current.cta_clicks_count,
          next_rate: rate(current.next_clicks_count, current.views_count),
          cta_rate: rate(current.cta_clicks_count, current.views_count),
          next_page_id: current.next_page_id
        }
        current = nxt
      end
      { key: head.slug, steps: chain }
    end
  end

  def rate(part, total)
    total.positive? ? ((part.to_f / total) * 100).round(1) : 0.0
  end
end
