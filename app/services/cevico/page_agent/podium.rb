# 🥇 PÓDIO das páginas (item 353) — como o pódio de ganchos, corpos e CTAs dos
# criativos, mas nas três partes de uma página:
#   titulo   o título que mais atrai (clique por aparição no Google; sem o
#            Google ligado, lead por visita)
#   corpo    o corpo que mais segura (leram até o fim)
#   convite  o convite que mais converte (clique no WhatsApp por visita)
# Só entra quem tem volume mínimo; cada lista vem ordenada, a 1ª é a campeã.
class Cevico::PageAgent::Podium
  MIN_VIEWS = Cevico::PageAgent::Rates::MIN_VIEWS
  MIN_IMPRESSIONS = Cevico::PageAgent::Rates::MIN_IMPRESSIONS

  def initialize(rows:, gsc: {}, pages: {})
    @rows = rows.select { |r| r[:page_id] }
    @gsc = gsc || {}
    @pages = pages || {}
  end

  def call
    { titulo: titles, corpo: bodies, convite: invites }
  end

  private

  def titles # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    with_google = @rows.filter_map do |row|
      g = @gsc[row[:page_id]]
      next if g.nil? || g[:impressions].to_i < MIN_IMPRESSIONS

      item(row, g[:ctr].to_f / 100, text: row.dig(:seo, :title).presence || row[:title], metric: 'clique por aparição no Google',
                                    extra: "#{g[:impressions]} aparições · posição #{g[:position].to_f.round(1).to_s.tr('.', ',')}")
    end
    return sort(with_google).map { |i| i.merge(source: 'google') } if with_google.size >= 2

    sort(@rows.filter_map do |row|
      next if row[:views].to_i < MIN_VIEWS

      item(row, row[:leads].to_f / row[:views], text: row.dig(:seo, :title).presence || row[:title], metric: 'lead por visita')
    end).map { |i| i.merge(source: 'leads') }
  end

  def bodies
    sort(@rows.filter_map do |row|
      scroll = row[:scroll] || {}
      next if row[:views].to_i < MIN_VIEWS || scroll.empty?

      item(row, scroll['100'].to_f / row[:views], text: @pages[row[:page_id]]&.subtitle.presence || row[:title], metric: 'leram até o fim',
                                                  extra: "metade: #{pct(scroll['50'].to_f / row[:views])}")
    end)
  end

  def invites
    sort(@rows.filter_map do |row|
      next if row[:views].to_i < MIN_VIEWS

      item(row, row[:cta].to_f / row[:views], text: @pages[row[:page_id]]&.cta_label.presence || 'Falar no WhatsApp',
                                              metric: 'clique no WhatsApp por visita', extra: "#{row[:cta]} clique(s) em #{row[:views]} visitas")
    end)
  end

  def item(row, value, text:, metric:, extra: nil)
    { page_id: row[:page_id], title: row[:title], emoji: row[:emoji], slug: row[:slug], public_url: row[:public_url],
      text: text.to_s[0, 160], value: value.round(4), value_text: pct(value), metric: metric, extra: extra,
      views: row[:views], leads: row[:leads], booked: row[:booked] }
  end

  def sort(list)
    list.sort_by { |i| [-i[:value], -i[:views].to_i] }.each_with_index.map { |i, idx| i.merge(rank: idx + 1) }
  end

  def pct(value)
    "#{format('%.1f', value.to_f * 100).tr('.', ',')}%"
  end
end
