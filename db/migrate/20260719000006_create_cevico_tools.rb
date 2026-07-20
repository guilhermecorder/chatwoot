# FERRAMENTAS da Academia (item 77): o Guilherme escreve ferramentas de
# trabalho em texto (scripts, métodos, checklists) e o time lê em página
# bonita dentro da Academia CEVICO. Aditiva.
class CreateCevicoTools < ActiveRecord::Migration[7.1]
  def change
    create_table :cevico_tools do |t|
      t.references :account, null: false, foreign_key: true
      t.string :title, null: false
      t.string :emoji, null: false, default: '🧰'
      t.string :category, null: false, default: ''                       # agrupamento livre (ex: Vendas, Atendimento)
      t.text :content, null: false, default: ''                          # texto com marcação leve (# título, - lista, **negrito**)
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true                   # rascunho = só o admin vê
      t.integer :created_by_id
      t.timestamps
    end
  end
end
