# 👓🪞 SUA ÓTICA — PROVA VIRTUAL / VISAGISMO (08/11/2026, ideia do Henrique):
# a cliente manda uma foto pelo WhatsApp, o sistema lê o formato do rosto,
# escolhe armações do estoque que combinam (regras de visagismo) e devolve a
# foto dela usando cada armação. Para isso a armação precisa de uma FOTO
# (ActiveStorage, sem coluna) e de três marcas no cadastro:
#   frame_shape      formato da armação (redonda, quadrada, gatinho, aviador…)
#   frame_fit        público (feminina, masculina, unissex)
#   try_on           entra na prova virtual? (padrão sim; a loja tira o que não quer mostrar)
#   visagismo_notes  observação livre da loja para o agente ("leve, boa p/ grau alto")
# Reversível (só colunas com padrão).
class AddVisagismoToOticaProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :otica_products, :frame_shape, :string, null: false, default: ''
    add_column :otica_products, :frame_fit, :string, null: false, default: ''
    add_column :otica_products, :try_on, :boolean, null: false, default: true
    add_column :otica_products, :visagismo_notes, :string, null: false, default: ''
  end
end
