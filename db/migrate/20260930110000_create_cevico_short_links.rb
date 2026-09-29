# 🔗 item 302 (30/09): LINK CURTO para as páginas de leitura. O link da análise
# do criativo carregava o token inteiro no endereço (mais de 300 letras). Agora
# o token fica guardado aqui e o endereço leva só um código de 10 letras.
class CreateCevicoShortLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :cevico_short_links do |t|
      t.references :account, null: false, foreign_key: true
      t.string :code, null: false
      t.string :kind, null: false
      t.text :token, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :cevico_short_links, :code, unique: true
    add_index :cevico_short_links, :expires_at
  end
end
