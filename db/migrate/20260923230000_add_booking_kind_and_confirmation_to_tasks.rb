# 📅 item 217 (23/09): o que CONTA como agendamento.
#   booking_kind  'agendamento' (padrão, nil = agendamento) | 'registro' =
#                 consulta que JÁ ESTAVA marcada fora do sistema (Oftalmofácil,
#                 telefone) e foi só lançada na Agenda — não é agendamento novo
#   confirmed_at  paciente respondeu SIM ao lembrete da véspera
#   declined_at   paciente respondeu NÃO ao lembrete da véspera
class AddBookingKindAndConfirmationToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :booking_kind, :string
    add_column :tasks, :confirmed_at, :datetime
    add_column :tasks, :declined_at, :datetime
  end
end
