# CENTRAL DO PACIENTE — Fase 2 (Espaço Nobre do Médico): anotações de
# consulta com campos rápidos + fotos de exames (ActiveStorage). ⚠️ LGPD:
# dado de SAÚDE é sensível — nasce como "anotação interna da clínica"
# (não substitui prontuário certificado), acesso restrito e auditável.
# Aditiva: só cria tabela nova.
class CreateCrmClinicalNotes < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_clinical_notes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :task, foreign_key: true # consulta da Agenda ligada (opcional)
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.string :doctor                       # nome oficial do médico da casa
      t.datetime :performed_at, null: false  # data da consulta anotada
      # campos rápidos: procedimento/técnica/lente, olho, refração, acuidade,
      # PIO, biomicroscopia, fundoscopia, conduta, exames pedidos
      t.jsonb :fields, default: {}, null: false
      t.text :observations
      t.timestamps
    end
    add_index :crm_clinical_notes, [:account_id, :contact_id, :performed_at],
              name: 'index_clinical_notes_on_account_contact_performed'
  end
end
