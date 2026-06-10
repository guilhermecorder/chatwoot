class AddStageTrackingToCrm < ActiveRecord::Migration[7.0]
  def change
    # Rastreia quando o card entrou na coluna atual
    add_column :crm_contacts, :stage_moved_at, :datetime

    # Histórico de movimentações entre colunas
    create_table :crm_contact_stage_logs do |t|
      t.bigint  :crm_contact_id, null: false
      t.bigint  :stage_id,       null: false
      t.string  :stage_name,     null: false   # desnormalizado para preservar histórico
      t.string  :stage_color                   # desnormalizado
      t.string  :event_type,     null: false, default: 'entered'  # entered | automation_fired
      t.datetime :entered_at,   null: false
      t.datetime :left_at                      # null = ainda nesta etapa
      t.integer  :duration_minutes             # calculado ao sair
      t.timestamps
    end

    add_index :crm_contact_stage_logs, :crm_contact_id
    add_index :crm_contact_stage_logs, [:crm_contact_id, :entered_at]
  end
end
