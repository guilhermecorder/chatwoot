# Item 324 (05/10): VALOR do agendamento em lugar próprio.
#   charges    = valores lançados à mão no card da Agenda — lista de
#                { label, amount, by_id, by_name, at } (quem lançou e quando)
#   particular = consulta particular (o valor pré-configurado é o do médico)
# Colunas novas, vazias: nenhum agendamento antigo muda.
class AddChargesAndParticularToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :charges, :jsonb, default: [], null: false
    add_column :tasks, :particular, :boolean, default: false, null: false
  end
end
