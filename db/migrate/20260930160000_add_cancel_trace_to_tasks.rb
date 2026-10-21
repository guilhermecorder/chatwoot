# 🗑️ item 304 (30/09): "Excluir" na Agenda apagava a consulta de verdade, sem
# rastro (30/09: a equipe apagou os "duplicados" do Tatuapé e os retornos
# sumiram). Agora excluir = cancelar, guardando QUEM e POR QUÊ — e a Lixeira
# restaura.
class AddCancelTraceToTasks < ActiveRecord::Migration[7.1]
  def change
    add_reference :tasks, :canceled_by, foreign_key: { to_table: :users }, null: true, index: true
    add_column :tasks, :cancel_reason, :string
  end
end
