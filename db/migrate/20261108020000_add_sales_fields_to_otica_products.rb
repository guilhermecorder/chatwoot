# 👓💬 VENDA PELO WHATSAPP (08/11/2026, 2ª etapa da ideia do Henrique): depois
# da prova virtual vem a consultoria de lentes e a negociação. Para isso o
# produto ganha:
#   max_discount_pct  até onde vai o desconto (%), por produto — a ferramenta
#                     conferir_desconto usa isto; o modelo nunca vê o piso
#   pitch             como explicar em 1 ou 2 frases simples (lente: pra quem é,
#                     o que resolve; armação: o diferencial)
# A imagem explicativa da lente usa a mesma `photo` da armação (ActiveStorage).
# Reversível (só colunas com padrão).
class AddSalesFieldsToOticaProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :otica_products, :max_discount_pct, :decimal, precision: 5, scale: 2, null: false, default: 0
    add_column :otica_products, :pitch, :string, null: false, default: ''
  end
end
