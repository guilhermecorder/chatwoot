# 📐 AS TAXAS de uma página lidas como gancho, corpo e CTA (item 353):
#   google    clique por aparição no Google (Search Console) — o TÍTULO atrai?
#   reading   leram até a metade — o CORPO segura?
#   cta       clique no WhatsApp por visita — o CONVITE convence?
#   arrival   lead por clique — a mensagem pronta chega na caixa?
#   booking   agendou por lead — a promessa da página se confirma no atendimento?
#   result    lead por visita — o resultado da página inteira
# Cada taxa só existe com VOLUME MÍNIMO (abaixo disso é nil, não zero).
module Cevico::PageAgent::Rates
  module_function

  MIN_VIEWS = 30
  MIN_CLICKS = 8
  MIN_LEADS = 5
  MIN_IMPRESSIONS = 30

  KEYS = %w[google reading cta arrival booking result].freeze
  SUM_KEYS = %i[views cta leads booked].freeze

  # row = linha do Cevico::TrafficReport; gsc = linha do Search Console da página (ou nil)
  def for(row, gsc = nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    views = row[:views].to_f
    cta = row[:cta].to_f
    leads = row[:leads].to_f
    scroll = row[:scroll] || {}
    half = scroll['50'].to_f
    {
      'google' => gsc && gsc[:impressions].to_i >= MIN_IMPRESSIONS ? (gsc[:ctr].to_f / 100).round(4) : nil,
      'reading' => views >= MIN_VIEWS && scroll.present? ? (half / views).clamp(0, 1).round(4) : nil,
      'cta' => views >= MIN_VIEWS ? (cta / views).round(4) : nil,
      'arrival' => cta >= MIN_CLICKS ? (leads / cta).clamp(0, 1).round(4) : nil,
      'booking' => leads >= MIN_LEADS ? (row[:booked].to_f / leads).round(4) : nil,
      'result' => views >= MIN_VIEWS ? (leads / views).round(4) : nil
    }
  end

  # soma várias linhas numa só (para a média da casa)
  def sum(rows)
    rows.each_with_object({ views: 0, cta: 0, leads: 0, booked: 0, scroll: Hash.new(0) }) do |r, acc|
      SUM_KEYS.each { |k| acc[k] += r[k].to_i }
      (r[:scroll] || {}).each { |mark, n| acc[:scroll][mark] += n.to_i }
    end
  end
end
