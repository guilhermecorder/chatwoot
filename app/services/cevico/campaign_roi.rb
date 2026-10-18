# 💰 ROI POR CAMPANHA (18/10): "queremos entender melhor o ROI dessa campanha
# específica, mas ela envia a pessoa pra mesma página".
#
# Junta, por campanha (utm_campaign do anúncio):
#   resultado  visitas, cliques no WhatsApp, leads, agendou, cirurgias e receita
#              — somados de todas as páginas (Cevico::TrafficReport)
#   custo      do Google Ads, por campanha (Crm::GoogleCampaignCostService, via GA4)
#
# Como uma campanha do relatório encontra o custo dela, na ordem de certeza:
#   1. ID   o anúncio manda utm_id={campaignid}; o Protocolo do clique guarda o
#           ID ao lado do utm_campaign → o ID mais visto para aquele nome
#   2. nome utm_campaign igual ao nome da campanha no Google (sem acento,
#           maiúscula, espaço ou símbolo)
# O gasto do Google que não encontrou nenhuma campanha rastreada aparece à
# parte ("gasto sem rastreio") — é dinheiro que ainda não dá para ligar a paciente.
class Cevico::CampaignRoi
  # quanto tempo para trás olhar os cliques para descobrir o ID de cada campanha
  ID_LOOKBACK = 120.days

  def initialize(account:, report:, costs:)
    @account = account
    @report = report
    @costs = costs || {}
  end

  def call
    {
      configured: @costs[:configured] == true,
      error: @costs[:error],
      campaigns: campaigns,
      untracked: untracked,
      totals: totals
    }
  end

  private

  def campaigns
    @campaigns ||= results_by_name.map { |name, row| with_cost(name, row) }
                                  .sort_by { |c| [-(c[:cost] || -1), -c[:leads], -c[:views]] }
  end

  # { nome => { views:, cta:, leads:, booked:, conversions:, revenue:, pages: [..] } }
  def results_by_name
    @report.rows.each_with_object({}) do |page, acc|
      (page[:campaigns] || {}).each { |name, bucket| add_result(acc, name, bucket, page[:title]) if name.present? }
    end
  end

  def add_result(acc, name, bucket, title)
    row = (acc[name] ||= blank.merge(pages: []))
    blank.each_key { |key| row[key] += bucket[key].to_f }
    row[:pages] << title unless row[:pages].include?(title)
  end

  def with_cost(name, row)
    match = match_for(name)
    cost = match&.dig(:cost)
    out = row.transform_values { |v| v.is_a?(Float) && (v % 1).zero? ? v.to_i : v }
    out.merge(name: name, revenue: row[:revenue].round(2), cost: cost,
              google_name: match&.dig(:name), campaign_id: match&.dig(:id), matched_by: match&.dig(:by),
              **ratios(cost, row))
  end

  def ratios(cost, row)
    return { cpl: nil, cost_per_booked: nil, cost_per_conversion: nil, roas: nil, roi: nil } if cost.nil? || cost.zero?

    {
      cpl: per(cost, row[:leads]),
      cost_per_booked: per(cost, row[:booked]),
      cost_per_conversion: per(cost, row[:conversions]),
      roas: (row[:revenue] / cost).round(2),
      roi: (((row[:revenue] - cost) / cost) * 100).round(1)
    }
  end

  def per(cost, count)
    count.to_f.positive? ? (cost / count).round(2) : nil
  end

  # cada campanha do Google entra em UM nome só — dois utm_campaign apontando
  # para o mesmo ID não podem contar o mesmo gasto duas vezes
  def match_for(name)
    free = google_rows.reject { |r| used_ids.include?(r[:id]) }
    row = free.find { |r| r[:id] == ids_by_name[name] }&.merge(by: 'id') || name_match(free, name)
    used_ids << row[:id] if row
    row
  end

  def name_match(free, name)
    key = simple(name)
    return nil if key.blank?

    free.find { |r| simple(r[:name]) == key }&.merge(by: 'nome')
  end

  # gasto do Google que nenhuma campanha rastreada reclamou
  def untracked
    campaigns # garante que o casamento já rodou
    google_rows.reject { |r| used_ids.include?(r[:id]) }.select { |r| r[:cost].positive? }
  end

  def totals
    tracked = campaigns.select { |c| c[:cost] }
    sums = %i[cost revenue leads booked].index_with { |key| tracked.sum { |c| c[key] } }
    sums.merge(cost: sums[:cost].round(2), revenue: sums[:revenue].round(2),
               untracked_cost: untracked.sum { |r| r[:cost] }.round(2),
               roas: sums[:cost].positive? ? (sums[:revenue] / sums[:cost]).round(2) : nil)
  end

  def google_rows
    @google_rows ||= Array(@costs[:campaigns]).map { |r| r.transform_keys(&:to_sym) }
  end

  def used_ids
    @used_ids ||= Set.new
  end

  # utm_campaign → ID da campanha mais visto nos Protocolos (cliques) recentes
  def ids_by_name
    @ids_by_name ||= begin
      pairs = @account.cevico_page_refs
                      .where(created_at: (@report.since_date - ID_LOOKBACK).beginning_of_day..@report.until_date.end_of_day)
                      .where("source_data ->> 'utm_id' IS NOT NULL AND source_data ->> 'campaign' <> ''")
                      .group(Arel.sql("source_data ->> 'campaign'"), Arel.sql("source_data ->> 'utm_id'"))
                      .count
      pairs.group_by { |(name, _id), _n| name }
           .transform_values { |list| list.max_by { |(_name, _id), n| n }.first.last }
    end
  end

  def simple(text)
    I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]/, '')
  end

  def blank
    { views: 0.0, cta: 0.0, leads: 0.0, booked: 0.0, conversions: 0.0, revenue: 0.0 }
  end
end
