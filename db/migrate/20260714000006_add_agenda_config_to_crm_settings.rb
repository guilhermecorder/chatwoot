# Janelas de avaliação dos médicos editáveis pela tela da Agenda
# (dia da semana, médico, unidade, horário e tamanho do bloco).
class AddAgendaConfigToCrmSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_settings, :agenda_config, :jsonb, null: false, default: {}
  end
end
