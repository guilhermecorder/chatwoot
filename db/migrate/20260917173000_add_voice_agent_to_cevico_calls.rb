# 🤖📞 Agente de Ligação (item 169): a mesma tabela cevico_calls passa a
# guardar as ligações atendidas/feitas pela assistente virtual (ElevenLabs)
# — quem cuidou (handled_by), o id da conversa lá (provider_call_id), o
# resultado em pt-BR (outcome), a análise crua e o custo. Duas tabelas
# novas: campanhas de ligação (a assistente liga para um público) e os
# contatos de cada campanha (fila, status e resultado por pessoa).
class AddVoiceAgentToCevicoCalls < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    add_column :cevico_calls, :handled_by, :string, null: false, default: 'human' # human | ai
    add_column :cevico_calls, :provider, :string          # 'elevenlabs' nas ligações da IA
    add_column :cevico_calls, :provider_call_id, :string  # conversation_id da ElevenLabs
    # agendou | remarcou | cancelou | quer_whatsapp | sem_interesse | recado | transferido | nao_atendeu | outro
    add_column :cevico_calls, :outcome, :string
    add_column :cevico_calls, :campaign_id, :bigint       # campanha de ligação (sem FK: a campanha pode ser apagada)
    add_column :cevico_calls, :analysis, :jsonb, null: false, default: {} # resumo/critérios/data_collection crus
    add_column :cevico_calls, :cost_usd, :decimal, precision: 12, scale: 6
    add_index :cevico_calls, [:account_id, :provider_call_id]
    add_index :cevico_calls, :campaign_id

    create_table :cevico_call_campaigns do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      # draft 0 | scheduled 1 | processing 2 | paused 3 | completed 4 | failed 5
      t.integer :status, null: false, default: 0
      t.jsonb :audience, null: false, default: {} # mesmas chaves da Campanha WhatsApp
      t.text :objective       # o que a assistente quer nesta ligação ({{campanha_objetivo}})
      t.text :first_message   # primeira frase (vazio = a da configuração)
      t.string :apply_label   # etiqueta aplicada a quem foi ligado
      t.jsonb :hours          # { start, end } (vazio = horário da configuração)
      t.integer :daily_cap, null: false, default: 50
      t.integer :concurrency, null: false, default: 2
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :stats, null: false, default: {} # { total, called, done, failed, skipped, outcomes: {} }
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :cevico_call_campaigns, [:account_id, :status]

    create_table :cevico_call_campaign_contacts do |t|
      t.references :call_campaign, null: false, foreign_key: { to_table: :cevico_call_campaigns, on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      # queued | calling | done | failed | skipped | no_permission
      t.string :status, null: false, default: 'queued'
      t.string :provider_conversation_id # conversation_id da ElevenLabs (liga o pós-chamada ao contato)
      t.bigint :call_id                  # Crm::Call criada para esta ligação
      t.string :outcome
      t.text :error
      t.integer :attempts, null: false, default: 0
      t.datetime :called_at
      t.timestamps
    end
    add_index :cevico_call_campaign_contacts, [:call_campaign_id, :contact_id], unique: true
    add_index :cevico_call_campaign_contacts, :provider_conversation_id
  end
end
