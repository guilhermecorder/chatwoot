# 👓📦 ACOMPANHAMENTO DO PEDIDO (08/11/2026): a O.S. ganha a hora em que ficou
# PRONTA (ready_at), para o vigia dos pedidos (Otica::OrderWatch) saber há
# quantos dias o óculos espera o cliente e para a Val virtual responder "já
# ficou pronto?" com a data certa. Reversível (coluna nula).
class AddReadyAtToOticaOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :otica_orders, :ready_at, :datetime
  end
end
