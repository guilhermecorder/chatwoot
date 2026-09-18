# 🗺️ Mensagens da jornada (item 168): motor nativo de mensagens-modelo por
# GATILHO DE DATA/ETAPA ao longo da jornada do paciente (substitui o N8N da
# confirmação cirúrgica). Duas tabelas: a regra (o quê, quando, para quem) e o
# registro de cada envio (1 por paciente × evento — idempotente).
class CreateCevicoJourneyMessages < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    create_table :cevico_journey_messages do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      # etapa da jornada onde a mensagem fica pendurada na tela
      # (lead | consulta | orcamento | cirurgia | pos_op | retorno)
      t.string :step, null: false, default: 'consulta'
      t.bigint :inbox_id
      # { kind: surgery|appointment|stage|label|call_missed, offset_days, at: 'HH:MM', stage_id, label }
      t.jsonb :trigger, null: false, default: {}
      # mesmas chaves da Campanha WhatsApp (include/exclude etiquetas e colunas)
      t.jsonb :audience, null: false, default: {}
      # { mode: template|text, template_params, message_preview, text }
      t.jsonb :content, null: false, default: {}
      t.string :approval, null: false, default: 'auto' # auto | review (Fila de hoje)
      t.boolean :expects_reply, null: false, default: false
      t.string :confirm_label
      t.boolean :decline_alert, null: false, default: true
      t.boolean :respect_quiet, null: false, default: true
      t.integer :position, null: false, default: 0
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :cevico_journey_messages, [:account_id, :active]

    create_table :cevico_journey_sends do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :journey_message, null: false, foreign_key: { to_table: :cevico_journey_messages, on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :conversation_id
      t.string :source_type
      t.bigint :source_id
      t.string :event_key, null: false
      t.datetime :scheduled_for, null: false
      # queued | pending_review | sent | skipped | failed | expired
      t.string :status, null: false, default: 'queued'
      t.datetime :sent_at
      t.string :reply # confirmed | declined | other
      t.datetime :replied_at
      t.text :reply_text
      t.text :error
      t.text :preview
      t.jsonb :variables, null: false, default: {}
      t.timestamps
    end
    add_index :cevico_journey_sends, [:journey_message_id, :event_key], unique: true
    add_index :cevico_journey_sends, [:account_id, :scheduled_for]
    add_index :cevico_journey_sends, [:account_id, :status]
  end
end
