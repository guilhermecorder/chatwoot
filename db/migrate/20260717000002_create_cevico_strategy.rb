# PAINEL ESTRATÉGICO CEVICO: a empresa estruturada por pilares
# (Aquisição de Pacientes, Operação Clínica, Financeiro/Tributário...).
# Cada pilar tem responsáveis, status de saúde (semáforo), nota de
# desempenho e a lista de estratégias/ações corretivas com dono, prazo
# e andamento. Aditiva.
class CreateCevicoStrategy < ActiveRecord::Migration[7.0]
  def change
    create_table :cevico_pillars do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :subtitle
      t.string :emoji, default: '🏛️'
      t.string :color, default: 'navy' # chave do gradiente na tela
      t.string :status, null: false, default: 'atencao' # otimo | atencao | critico
      t.text :health_note # desempenho/status atual, escrito pelo gestor
      t.jsonb :owner_ids, null: false, default: [] # responsáveis (ids de usuário)
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :cevico_pillars, [:account_id, :position]

    create_table :cevico_strategies do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pillar, null: false, foreign_key: { to_table: :cevico_pillars }
      t.string :kind, null: false, default: 'estrategia' # estrategia | correcao
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: 'andamento' # ideia | andamento | concluida | pausada
      t.integer :owner_id # responsável por ESTA estratégia (id de usuário)
      t.date :due_on
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :cevico_strategies, [:account_id, :kind]
  end
end
