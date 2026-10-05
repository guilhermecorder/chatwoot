# Item 322 (04/10): FONTES DE PACIENTES + CARIMBO DE ORIGEM.
# Pedido do Guilherme: "quero ser capaz de gerenciar pacientes de diversas
# fontes; cada fonte com o seu ambiente isolado" — começando pelo Oftalmofácil.
#
#   cevico_sources     = o cadastro das fontes (CEVICO, Oftalmofácil, …): cada
#                        uma dona dos seus funis e das suas caixas de entrada
#   cevico_source_id   = DE QUEM É o registro (gravado na hora em que nasce)
#   cevico_born_via    = COMO nasceu: paciente | equipe | robo | sync | carga |
#                        integracao (vazio = registro anterior ao carimbo)
#
# Só acrescenta colunas vazias (rápido, sem travar tabela). O passado é
# preenchido depois, pela tela Fontes de pacientes ou pelo robô da madrugada.
class CreateCevicoSources < ActiveRecord::Migration[7.1]
  STAMPED = %i[contacts crm_contacts crm_contact_stage_logs tasks cevico_oftalmofacil_surgeries].freeze

  def change
    create_table :cevico_sources do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :key, null: false
      t.string :name, null: false
      t.string :kind, null: false, default: 'partner'
      t.string :color
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end
    add_index :cevico_sources, [:account_id, :key], unique: true

    STAMPED.each do |table|
      add_column table, :cevico_source_id, :bigint
      add_column table, :cevico_born_via, :string
    end
  end
end
