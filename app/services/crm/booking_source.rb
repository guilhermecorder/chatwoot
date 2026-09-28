# 🤖 Quem marcou a consulta: o Atendente de IA (Secretário, Atendente de
# Agendamento, Pós-op, Ligação) deixa a marca na descrição da tarefa; sem
# marca = equipe. Uma regra só, usada pelos Agendamentos e pelo Meu Painel.
module Crm::BookingSource
  module_function

  IA_MARKS = /pela IA|pelo Atendente|Atendente de Agendamento|Atendente P[oó]s|Secret[aá]rio da Agenda|Agente de Liga/i

  def of(task)
    task.description.to_s.match?(IA_MARKS) ? 'ia' : 'equipe'
  end

  # SQL equivalente (para contar em lote)
  SQL_IA = "tasks.description ~* 'pela IA|pelo Atendente|Atendente de Agendamento|Atendente P[oó]s|Secret[aá]rio da Agenda|Agente de Liga'".freeze
end
