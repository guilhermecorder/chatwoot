# Indicadores do Meu Painel: consulta CANCELADA (canceled_at) e contagem de
# REAGENDAMENTOS (incrementa quando o dia/horário da consulta muda).
class AddCancelFieldsToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :canceled_at, :datetime
    add_column :tasks, :rescheduled_count, :integer, null: false, default: 0
  end
end
