# PÁGINAS CEVICO: sites públicos para anunciar procedimentos, quebrar
# objeções e nutrir pacientes em cada estágio da jornada (captação,
# pré-consulta, pré-cirurgia, pós-operatório). Base preparada para SEO
# (meta title/description próprios, URL limpa /p/:slug). Aditiva.
class CreateCevicoPages < ActiveRecord::Migration[7.0]
  def change
    create_table :cevico_pages do |t|
      t.references :account, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      # estágio da jornada: captacao | pre_consulta | pre_cirurgia | pos_operatorio
      t.string :category, null: false, default: 'captacao'
      t.string :status, null: false, default: 'draft' # draft | published
      t.string :emoji
      t.string :color
      t.string :subtitle
      t.text :body # conteúdo em markdown
      t.string :meta_title       # SEO: título no Google
      t.text :meta_description   # SEO: descrição no Google
      t.string :cta_label
      t.string :cta_url          # ex.: link do WhatsApp da clínica
      t.bigint :views_count, default: 0, null: false
      t.timestamps
    end
    add_index :cevico_pages, :slug, unique: true
    add_index :cevico_pages, [:account_id, :category]
  end
end
