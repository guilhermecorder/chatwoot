# Thread de solicitações/ajuda dentro da tarefa: quem recebe pode pedir
# esclarecimento a quem criou (e vice-versa), sem sair da tela de Tarefas.
# Formato: [{ "user_id", "name", "text", "at" }, ...]
class AddCommentsToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :comments, :jsonb, null: false, default: []
  end
end
