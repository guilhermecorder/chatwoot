# Integração com Google Sheets: o Guilherme cola o link da planilha de
# cirurgias (compartilhada como "qualquer pessoa com o link pode ver") e o
# sistema importa os dados para o Dashboard CEVICO.
class AddSheetsConfigToCrmSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_settings, :sheets_config, :jsonb, null: false, default: {}
  end
end
