# 🏥 item 300 (30/09): DE QUEM é o paciente do agendamento — 'cevico' ou
# 'oftalmofacil'. A equipe escolhe no formulário da Agenda (obrigatório ao
# criar). É o que manda o lembrete de confirmação pela caixa certa e o card
# para o CRM certo. nil = agendamento antigo (vale a regra de antes: etiqueta
# e funil do paciente).
class AddOriginToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :origin, :string
  end
end
