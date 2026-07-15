# Config livre por coluna do CRM. Primeiro uso: main_inbox_ids — as caixas
# de entrada PRINCIPAIS da coluna (o balão do card prioriza a conversa
# dessas caixas e o "Iniciar conversa" já vem com a caixa certa).
class AddSettingsToCrmStages < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_stages, :settings, :jsonb, null: false, default: {}
  end
end
