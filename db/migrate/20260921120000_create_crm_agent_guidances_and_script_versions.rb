# ✍️ Orientações dos atendentes + histórico do Roteiro (rodada 191).
#
# crm_agent_guidances: o admin (ou o 👎 da tela Sombra) registra "o agente
# respondeu X, deveria ter respondido Y, regra para o futuro Z" e escolhe em
# qual seção do Roteiro (ou nos passos do agente) isso entra. "Aplicar"
# escreve no Roteiro; a orientação fica como histórico do porquê.
#
# crm_script_versions: foto do Roteiro (ou do prompt da etapa do agente)
# ANTES de cada mudança — dá para "voltar para esta" a qualquer momento.
class CreateCrmAgentGuidancesAndScriptVersions < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    create_table :crm_agent_guidances do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :agent_key, null: false # atendente_agendamento | atendente_pos | instagram | comments
      t.integer :conversation_id # display_id da conversa de origem (como aparece na tela)
      t.bigint :message_id # nota de sombra que originou (evita duplicar o sinal do 👎)
      t.string :source, null: false, default: 'manual' # manual | sombra
      t.text :patient_excerpt
      t.text :agent_text
      t.text :ideal_reply
      t.text :rule
      t.string :target_section # persona | form_rules | official_data | objections | handoff | stage
      t.string :status, null: false, default: 'pending' # pending | applied | ignored
      t.datetime :applied_at
      t.bigint :created_by_id
      t.bigint :applied_by_id
      t.timestamps
    end
    add_index :crm_agent_guidances, [:account_id, :status]
    add_index :crm_agent_guidances, [:account_id, :message_id]

    create_table :crm_script_versions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false, default: 'script' # script (Roteiro inteiro) | stage (prompt da etapa de 1 agente)
      t.string :agent_key
      t.jsonb :content, null: false, default: {}
      t.string :note
      t.bigint :created_by_id
      t.bigint :guidance_id
      t.timestamps
    end
    add_index :crm_script_versions, [:account_id, :created_at]
  end
end
