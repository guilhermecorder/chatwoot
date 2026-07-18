# Metas com dono e caminho (pedido 17/07): cada indicador do plano do mês
# pode ter um RESPONSÁVEL do time e um texto "o que é preciso para alcançar"
# — o admin prepara, o time vê no Painel de Metas.
class AddIndicatorMetaToCevicoGoalPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :cevico_goal_plans, :indicator_meta, :jsonb, null: false, default: {}
  end
end
