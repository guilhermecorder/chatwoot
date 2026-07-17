# PÁGINAS PRO: testes A/B (variações de headline/CTA servidas no mesmo
# slug), comentários do time no estúdio de copy, e o PLANEJAMENTO DE
# CONTEÚDOS (workflow kanban: ideia → copy → produção → revisão →
# publicado). Aditiva.
class CreatePagesPro < ActiveRecord::Migration[7.0]
  def change
    add_column :cevico_pages, :ab_variants, :jsonb, null: false, default: []
    add_column :cevico_pages, :team_comments, :jsonb, null: false, default: []

    create_table :cevico_content_items do |t|
      t.references :account, null: false, foreign_key: true
      t.string :title, null: false
      t.string :format, null: false, default: 'post' # reels | carrossel | post | anuncio | pagina | email
      t.string :stage, null: false, default: 'ideia' # ideia | copy | producao | revisao | publicado
      t.integer :owner_id # responsável (id de usuário)
      t.date :due_on
      t.text :notes
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :cevico_content_items, [:account_id, :stage]
  end
end
