# Comparecimento e indicação de cirurgia nas consultas da Agenda:
# - attendance: 'attended' (compareceu) | 'missed' (faltou) | nil (sem conferência)
# - surgery_indication: 'indicated' | 'not_indicated' | nil
# - indicated_procedure: procedimento escolhido quando a cirurgia é indicada
# A conferência é feita pela equipe no fim do dia, na lista da Agenda.
class AddAttendanceToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :attendance, :string
    add_column :tasks, :surgery_indication, :string
    add_column :tasks, :indicated_procedure, :string
  end
end
