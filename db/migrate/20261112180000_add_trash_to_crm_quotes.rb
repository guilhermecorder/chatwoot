# 🗑️ 12/11/2026 (pedido do Guilherme): orçamento excluído vai para a LIXEIRA, com quem excluiu, quando e o
# motivo. Os PDFs ficam guardados; só o dono da conta vê a lixeira e restaura.
class AddTrashToCrmQuotes < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_quotes, :deleted_at, :datetime
    add_column :crm_quotes, :deleted_by_id, :bigint
    add_column :crm_quotes, :delete_reason, :string
    add_index :crm_quotes, [:account_id, :deleted_at]
  end
end
