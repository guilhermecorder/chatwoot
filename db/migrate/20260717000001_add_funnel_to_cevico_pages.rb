# CEVICO — funil de páginas + rastreamento (pedido 17/07):
# - next_page_id: "reapontar para outra página da CEVICO" (funil de conteúdo:
#   captação → aprofundamento → convite pro WhatsApp)
# - cta_clicks_count / next_clicks_count: cliques no convite (WhatsApp) e no
#   próximo passo do funil
# - daily_stats: contadores por dia {"2026-07-17" => {"view" => 10, "cta" => 2,
#   "next" => 3, "de" => {"pagina-origem" => 4}}} — base p/ medir conversão
class AddFunnelToCevicoPages < ActiveRecord::Migration[7.1]
  def change
    add_reference :cevico_pages, :next_page, foreign_key: { to_table: :cevico_pages }, index: true, null: true
    add_column :cevico_pages, :cta_clicks_count, :integer, default: 0, null: false
    add_column :cevico_pages, :next_clicks_count, :integer, default: 0, null: false
    add_column :cevico_pages, :daily_stats, :jsonb, default: {}, null: false
  end
end
