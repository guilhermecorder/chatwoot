# Registros de SAÚDE do HUB (segmento saude): treino, dieta e corpo.
# O payload de cada dia vai livre em data (jsonb); fichas de treino, plano
# alimentar e metas moram em crm_settings.agenda_config['health'].
class CreateHubHealthRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :hub_health_records do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :user_id
      t.string :kind, null: false
      t.date :record_date, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :hub_health_records, [:account_id, :kind, :record_date]
  end
end
