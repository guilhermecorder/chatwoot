# RENOVAR O AMBIENTE (item 95): 5 min depois de tudo concluído, os cards
# vão para a COLUNA OCULTA (archived_at) e a tela nasce limpa pro próximo
# ciclo — nas Tarefas e no Planejamento de conteúdos. Aditiva.
class AddArchivedAtToTasksAndContentItems < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :archived_at, :datetime
    add_column :cevico_content_items, :archived_at, :datetime
  end
end
