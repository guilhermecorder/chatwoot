# 🎨 item 290 (29/09): COR por agendamento na Agenda (pedido dele, "parecido
# com o Google Agenda"): a equipe pinta a consulta/cirurgia/exame para se
# organizar. nil = cor padrão do tipo. É organização livre — não entra em
# nenhum indicador. Só aceita as cores de Task::COLORS.
class AddColorToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :color, :string
  end
end
