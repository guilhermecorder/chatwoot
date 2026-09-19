# Central de Criativos (item 172): guarda os anúncios da conta de anúncios da
# Meta com o criativo (gancho/corpo/CTA/miniatura/formato) e as métricas
# DIÁRIAS por anúncio (inclusive vídeo e conversas), para a tela cruzar o
# desempenho da plataforma com a jornada do CRM sem bater na API a cada
# abertura. Preenchidas pelo Crm::AdInsightsSyncService.
class CreateCevicoAdCreativesAndInsights < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength
  def change
    create_table :cevico_ad_creatives do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :ad_id, null: false
      t.string :ad_name
      t.string :adset_id
      t.string :adset_name
      t.string :campaign_id
      t.string :campaign_name
      t.string :effective_status # ACTIVE | PAUSED | ARCHIVED | ... (como a Meta devolve)
      t.string :format, null: false, default: 'other' # video | image | carousel | dynamic | other
      # { title, body, cta_type, description, thumbnail_url, image_url, video_id, permalink,
      #   titles: [], bodies: [], ctas: [], descriptions: [] } — os arrays vêm do criativo dinâmico
      t.jsonb :creative, null: false, default: {}
      t.datetime :synced_at
      t.timestamps
    end
    add_index :cevico_ad_creatives, [:account_id, :ad_id], unique: true
    add_index :cevico_ad_creatives, [:account_id, :campaign_id]

    create_table :cevico_ad_insights do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :ad_id, null: false
      t.date :date, null: false
      # { spend, impressions, reach, frequency, clicks, link_clicks, plays_3s, plays_2s, thruplay,
      #   p25, p50, p75, p100, avg_watch, conversations, first_replies, leads, post_engagement,
      #   actions: { action_type => valor } }
      t.jsonb :metrics, null: false, default: {}
      t.timestamps
    end
    add_index :cevico_ad_insights, [:account_id, :ad_id, :date], unique: true
    add_index :cevico_ad_insights, [:account_id, :date]
  end
  # rubocop:enable Metrics/MethodLength
end
