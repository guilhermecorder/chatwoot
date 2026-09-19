# Exporta o que é NOSSO: cada anúncio × dia guardado em cevico_ad_insights,
# com o criativo (gancho, corpo, CTA) ao lado — CSV para planilha ou backup
# fora do sistema (item 174, independência da Meta).
require 'csv'

class Crm::CreativesExport
  HEADERS = ['Data', 'ID do anúncio', 'Anúncio', 'Campanha', 'Conjunto', 'Formato', 'Status na Meta',
             'Gancho', 'Corpo', 'CTA', 'Investimento', 'Impressões', 'Alcance', 'Frequência', 'Cliques no link',
             'Plays 3 s', 'ThruPlay', '25%', '50%', '75%', '100%', 'Conversas iniciadas', 'Custo por conversa',
             'Miniatura guardada'].freeze

  def initialize(account:, since_date: nil, until_date: nil)
    @account = account
    @since_date = since_date
    @until_date = until_date
  end

  def call
    creatives = Crm::AdCreative.where(account_id: @account.id).with_attached_thumbnail.index_by(&:ad_id)
    csv = CSV.generate(col_sep: ';', force_quotes: false) do |out|
      out << HEADERS
      scope.find_each(batch_size: 2000) { |row| out << line(row, creatives[row.ad_id]) }
    end
    # BOM: o Excel em português abre com acentos certos e ";" como separador
    "\uFEFF#{csv}"
  end

  def filename
    "cevico-criativos-#{Date.current.iso8601}.csv"
  end

  private

  def scope
    s = Crm::AdInsight.where(account_id: @account.id).order(:date, :ad_id)
    s = s.where(date: @since_date..) if @since_date
    s = s.where(date: ..@until_date) if @until_date
    s
  end

  # rubocop:disable Metrics/AbcSize
  def line(row, creative)
    m = row.metrics || {}
    conv = m['conversations'].to_f
    [
      row.date.iso8601, row.ad_id, creative&.ad_name, creative&.campaign_name, creative&.adset_name,
      creative&.format_label, creative&.effective_status,
      creative&.hook, creative&.body, creative ? Crm::AdCreativeParser.cta_label(creative.cta) : nil,
      num(m['spend']), m['impressions'].to_i, m['reach'].to_i, num(m['frequency']), m['link_clicks'].to_i,
      m['plays_3s'].to_i, m['thruplay'].to_i, m['p25'].to_i, m['p50'].to_i, m['p75'].to_i, m['p100'].to_i,
      conv.to_i, conv.positive? ? num(m['spend'].to_f / conv) : nil,
      creative&.thumbnail_stored? ? 'sim' : 'não'
    ]
  end
  # rubocop:enable Metrics/AbcSize

  # vírgula decimal, como o Excel em português espera
  def num(value)
    format('%.2f', value.to_f).tr('.', ',')
  end
end
