# 🏥 item 228 (24/09): agendamentos que NASCEM em outro sistema (Oftalmofácil)
# entram na Agenda com a origem marcada — para diferenciar na tela e nunca
# duplicar:
#   source        'oftalmofacil' (nil = nasceu aqui)
#   source_detail parceiro de aquisição lá (nome do fornecedor/clínica)
#   external_ref  chave do item no sistema de origem (idempotência do sync)
class AddSourceToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :source, :string
    add_column :tasks, :source_detail, :string
    add_column :tasks, :external_ref, :string
    add_index :tasks, [:account_id, :external_ref], unique: true, where: 'external_ref IS NOT NULL',
                                                    name: 'index_tasks_on_account_and_external_ref'
  end
end
