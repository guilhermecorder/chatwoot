# ⚡ item 237 (25/09): índices que o Meu Painel, o cesto de indicadores e a
# taxa oficial de agendamento (item 233) usam o tempo todo e não existiam —
# criados SEM travar as tabelas (concurrently), um de cada vez.
class AddCevicoDashboardIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :crm_contact_stage_logs, %i[stage_id entered_at], algorithm: :concurrently,
                                                                name: 'index_crm_stage_logs_on_stage_and_entered_at', if_not_exists: true
    add_index :contacts, %i[account_id created_at], algorithm: :concurrently,
                                                    name: 'index_contacts_on_account_and_created_at', if_not_exists: true
    add_index :tasks, %i[account_id task_type due_at], algorithm: :concurrently,
                                                       name: 'index_tasks_on_account_type_due', if_not_exists: true
    add_index :tasks, %i[account_id task_type created_at], algorithm: :concurrently,
                                                           name: 'index_tasks_on_account_type_created', if_not_exists: true
    add_index :messages, %i[conversation_id message_type created_at], algorithm: :concurrently,
                                                                      name: 'index_messages_on_conversation_type_created', if_not_exists: true
  end
end
