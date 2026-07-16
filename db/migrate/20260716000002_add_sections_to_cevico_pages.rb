# Construtor de Páginas v2: a página deixa de ser um texto corrido e vira
# uma pilha de SEÇÕES (hero, texto, benefícios, FAQ, depoimento, CTA,
# experiência de visão...), cada uma com efeito visual próprio.
# Aditiva: páginas antigas continuam com o corpo markdown (sections = []).
class AddSectionsToCevicoPages < ActiveRecord::Migration[7.1]
  def change
    add_column :cevico_pages, :sections, :jsonb, null: false, default: []
  end
end
