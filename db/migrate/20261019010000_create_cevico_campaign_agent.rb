# 🎯 AGENTE DE CAMPANHAS (item 352, 19/10/2026 — "um sistema/dispositivo pra
# verificar resultados de campanha, indicadores primários/secundários/
# terciários, subir e otimizar campanhas").
#
# Duas tabelas:
#   cevico_campaign_days     a FOTO DIÁRIA do Google por campanha (custo, cliques,
#                            impressões) lida do GA4 — a Meta já tem a dela por
#                            anúncio em cevico_ad_insights. Sem foto não há
#                            tendência, "nossa média" de 360 dias nem antes × depois.
#   cevico_campaign_actions  a FILA DE RECOMENDAÇÕES do agente: cada uma anda
#                            sugerida → aprovada → aplicada → aprendizado (antes ×
#                            depois com veredito), ou descartada/expirada.
class CreateCevicoCampaignAgent < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def change
    create_table :cevico_campaign_days do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :channel, null: false, default: 'google' # google (a Meta mora em cevico_ad_insights)
      t.string :campaign_id, null: false
      t.string :campaign_name
      t.date :date, null: false
      t.decimal :spend, precision: 12, scale: 2, null: false, default: 0
      t.integer :clicks, null: false, default: 0
      t.integer :impressions, null: false, default: 0
      t.timestamps
    end
    add_index :cevico_campaign_days, [:account_id, :channel, :campaign_id, :date], unique: true, name: 'index_campaign_days_unique_day'
    add_index :cevico_campaign_days, [:account_id, :date]

    create_table :cevico_campaign_actions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :channel, null: false            # meta | google
      t.string :level, null: false              # channel | campaign | adset | ad
      t.string :ref_id, null: false             # id na plataforma (ou a chave do canal)
      t.string :ref_name
      t.string :campaign_id
      t.string :campaign_name
      t.string :rule, null: false               # custo_alto, sem_resultado, campea, fadiga…
      t.string :kind, null: false               # pause | budget_up | budget_down | new_creative | audience | page | quality | pacing | watch
      t.string :severity, null: false, default: 'atencao' # alerta | atencao | oportunidade | info
      t.string :status, null: false, default: 'suggested' # suggested | approved | applied | dismissed | expired
      t.string :key, null: false                # canal:nível:id:regra — evita repetir a mesma sugestão aberta
      t.string :title, null: false
      t.text :evidence
      t.text :suggestion
      t.string :expected
      t.jsonb :payload, null: false, default: {}        # { pct, budget_from, budget_to, window_days, baseline… }
      t.jsonb :metrics_before, null: false, default: {} # a janela que gerou a sugestão
      t.jsonb :metrics_after, null: false, default: {}  # a janela depois de aplicar
      t.string :outcome                                 # better | worse | same | saved | early
      t.date :suggested_on, null: false
      t.datetime :decided_at
      t.bigint :decided_by_id
      t.datetime :applied_at
      t.string :applied_mode                            # api | manual
      t.datetime :learned_at
      t.text :error
      t.timestamps
    end
    add_index :cevico_campaign_actions, [:account_id, :status]
    add_index :cevico_campaign_actions, [:account_id, :key, :suggested_on]
    add_index :cevico_campaign_actions, [:account_id, :channel, :ref_id]
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
end
