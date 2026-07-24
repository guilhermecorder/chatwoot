# Rastreamento de origem das Páginas (plano 100+ páginas com ads):
# - custom_html: página HTML pronta ANEXADA no ambiente (feita fora do
#   Construtor) — servida como veio, com o rastreio injetado.
# - cevico_page_traffic: agregado por página/dia/origem/campanha (visitas e
#   cliques no convite) — alimenta a aba Resultados sem guardar visita a visita.
# - cevico_page_refs: o "Protocolo" — código curto gerado no clique do
#   WhatsApp que liga o paciente da caixa à página/anúncio de origem
#   (Google Ads via gclid/utm, Google orgânico, Meta, funil, direto).
class AddPageTrackingAndCustomHtml < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    add_column :cevico_pages, :custom_html, :text

    create_table :cevico_page_traffic do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :cevico_page, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.string :source, null: false, default: 'direto'
      t.string :campaign, null: false, default: ''
      t.integer :views, null: false, default: 0
      t.integer :cta_clicks, null: false, default: 0
      t.timestamps
    end
    add_index :cevico_page_traffic, [:cevico_page_id, :date, :source, :campaign],
              unique: true, name: 'index_page_traffic_unique_bucket'
    add_index :cevico_page_traffic, [:account_id, :date]

    create_table :cevico_page_refs do |t|
      t.references :account, null: false, foreign_key: true, index: false
      # nulo = Protocolo gerado no HUB (porta de entrada na raiz do domínio)
      t.references :cevico_page, null: true, foreign_key: true
      t.string :token, null: false
      t.jsonb :source_data, null: false, default: {}
      t.references :contact, foreign_key: true
      t.timestamps
    end
    add_index :cevico_page_refs, :token, unique: true
    add_index :cevico_page_refs, [:account_id, :created_at]
  end
end
