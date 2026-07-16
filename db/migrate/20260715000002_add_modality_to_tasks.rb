# Modalidade da consulta na Agenda: avaliacao (padrão) | retorno | exames.
# Alimenta a ocupação por tipo — quanto da agenda está com avaliação nova
# versus retorno/exames. Aditiva: consultas antigas ficam NULL (= avaliação).
class AddModalityToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :modality, :string
  end
end
