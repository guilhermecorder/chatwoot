# 📞 Chamadas nativas de WhatsApp (item 167): uma linha por ligação recebida
# ou feita pela caixa da API oficial da Meta — quem ligou, quem atendeu,
# quanto esperou, quanto falou, gravação e transcrição. É a fonte do card na
# conversa, do popup do time e do Dashboard de Ligações. Idempotente pelo
# meta_call_id (id da chamada na Meta).
class CreateCevicoCalls < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    create_table :cevico_calls do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :contact, null: true, foreign_key: { on_delete: :nullify }
      t.references :conversation, null: true, foreign_key: { on_delete: :nullify }, index: false
      # atendente que atendeu (recebida) ou que ligou (feita)
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      # mensagem-card na conversa (sem FK: a conversa pode ser apagada)
      t.bigint :message_id
      t.string :meta_call_id, null: false
      t.integer :direction, null: false, default: 0 # inbound 0 | outbound 1
      # ringing 0 | accepted 1 | completed 2 | missed 3 | rejected 4 | failed 5 | canceled 6
      t.integer :status, null: false, default: 0
      t.string :wa_id          # número do paciente (dígitos, como vem da Meta)
      t.string :display_name   # profile.name do WhatsApp
      t.datetime :started_at
      t.datetime :answered_at
      t.datetime :ended_at
      t.integer :duration      # segundos falados (terminate.duration; fallback fim − atendida)
      # completed | not_answered | rejected | outside_hours | failed | canceled | hangup
      t.string :end_reason
      t.string :error_code
      t.text :error_message
      t.text :sdp_offer        # recebida: oferta da Meta (apagada depois de atender/encerrar)
      t.text :sdp_answer       # feita: resposta da Meta (apagada no fim)
      t.jsonb :events, null: false, default: [] # linha do tempo crua [{at, event, status, raw}]
      t.integer :recording_duration
      t.string :recording_mime
      t.text :transcript
      t.string :transcript_status # nil | pending | processing | done | failed | skipped
      t.text :transcript_error
      t.text :summary
      t.datetime :transcribed_at
      t.boolean :simulated, null: false, default: false # simulação local (rake) — sem Meta/WebRTC
      t.timestamps
    end
    add_index :cevico_calls, [:account_id, :meta_call_id], unique: true
    add_index :cevico_calls, [:account_id, :started_at]
    add_index :cevico_calls, [:account_id, :status]
  end
end
