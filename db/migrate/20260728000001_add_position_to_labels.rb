# Etiquetas ORDENÁVEIS: o admin define a ordem que o time vê (setinhas na
# tela de Etiquetas). Backfill preserva a ordem alfabética atual — nada
# muda de lugar no deploy até alguém reordenar de propósito.
class AddPositionToLabels < ActiveRecord::Migration[7.1]
  def up
    add_column :labels, :position, :integer

    execute <<~SQL.squish
      UPDATE labels SET position = ranked.rn
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY title ASC) AS rn
        FROM labels
      ) ranked
      WHERE labels.id = ranked.id
    SQL
  end

  def down
    remove_column :labels, :position
  end
end
