# 📅 LINHA DO TEMPO de UMA página (item 353): visitas, cliques no WhatsApp e
# leads por dia nos últimos N dias, com as MARCAS do que mudou — cada insight
# aplicado (coleção de insights) e a última alteração da página — para o olho
# ver o antes × depois no próprio gráfico.
class Cevico::PageAgent::Timeline
  DEFAULT_DAYS = 90

  def initialize(account:, page:, days: DEFAULT_DAYS, until_date: Date.current)
    @account = account
    @page = page
    @days = days.to_i.clamp(7, 365)
    @until_date = until_date
  end

  def call
    dates = (since..@until_date).to_a
    traffic = traffic_by_day
    leads = leads_by_day
    {
      page_id: @page.id, title: @page.title, since: since.iso8601, until: @until_date.iso8601,
      labels: dates.map { |d| d.strftime('%d/%m') }, dates: dates.map(&:iso8601),
      views: dates.map { |d| traffic.dig(d, 0).to_i }, cta: dates.map { |d| traffic.dig(d, 1).to_i }, leads: dates.map { |d| leads[d].to_i },
      marks: marks(dates)
    }
  end

  private

  def since
    @since ||= @until_date - (@days - 1)
  end

  def traffic_by_day
    @account.cevico_page_traffic.where(cevico_page_id: @page.id, date: since..@until_date).group(:date)
            .pluck(:date, Arel.sql('SUM(views)'), Arel.sql('SUM(cta_clicks)')).to_h { |d, v, c| [d, [v, c]] }
  end

  def leads_by_day
    @account.contacts
            .where("(additional_attributes -> 'page_ads' ->> 'page_id') = ?", @page.id.to_s)
            .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz BETWEEN ? AND ?",
                   since.beginning_of_day, @until_date.end_of_day)
            .pluck(Arel.sql("additional_attributes -> 'page_ads' ->> 'captured_at'"))
            .each_with_object(Hash.new(0)) { |at, h| h[Time.zone.parse(at.to_s)&.to_date] += 1 }
  end

  # [{ date, index, title, kind }] — insights aplicados nesta página + última alteração
  def marks(dates) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    applied = Cevico::InsightLog.new(@account).list.select { |e| e['page_id'] == @page.id && e['status'] == 'done' && e['applied_at'].present? }
    list = applied.map { |e| { date: e['applied_at'], title: e['title'], kind: 'insight' } }
    list << { date: @page.updated_at.to_date.iso8601, title: 'Página alterada', kind: 'edit' } if @page.updated_at.to_date >= since
    placed = list.filter_map do |m|
      index = dates.index { |d| d.iso8601 == m[:date].to_s[0, 10] }
      index && m.merge(index: index)
    end
    placed.sort_by { |m| m[:index] }
  end
end
