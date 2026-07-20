# PALAVRAS-CHAVE por página (item 72): o admin escolhe as palavras que a
# página ataca no Google; entram na meta tag pública e viram filtro na
# Análise de Páginas. Aditiva.
class AddSeoKeywordsToCevicoPages < ActiveRecord::Migration[7.1]
  def change
    add_column :cevico_pages, :seo_keywords, :string
  end
end
