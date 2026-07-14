# Agenda vira agenda de CONSULTAS: além de nome (title), dia/horário (due_at)
# e unidade (unit), cada agendamento guarda telefone, problema (catarata,
# refrativa, exames...) e médico.
class AddAppointmentFieldsToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :phone, :string
    add_column :tasks, :procedure, :string
    add_column :tasks, :doctor, :string
  end
end
