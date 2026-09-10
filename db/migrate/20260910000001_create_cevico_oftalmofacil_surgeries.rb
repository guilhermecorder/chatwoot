# 🏥 Espelho das cirurgias do OftalmoFácil (item 157): cada linha é UM item
# de agendamento (SCHEDULING_ITEMS) da CEVICO lá dentro, lido pelo
# sincronizador (usuário só-leitura no MySQL dele). É a fonte da aba
# Lucratividade e da ficha cirúrgica no Espaço do Paciente; o card do CRM
# recebe só o valor. Idempotente pelo item_token (SCH_ITE_TOKEN).
class CreateCevicoOftalmofacilSurgeries < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :cevico_oftalmofacil_surgeries do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :contact, null: true, foreign_key: true
      t.string :item_token, null: false
      t.integer :scheduling_id
      t.integer :item_id
      # status como veio (id + rótulo) e a classificação nossa
      # (agendada/realizada/cancelada/ausente/aguardando_pagamento/outro)
      t.string :status_id
      t.string :status_label
      t.string :status_kind, null: false, default: 'outro'
      # paciente como estava no agendamento (denormalizado lá)
      t.string :patient_name
      t.string :patient_cpf
      t.string :patient_phone
      t.string :patient_email
      # partes: fornecedor (quem indicou = CEVICO), prestador (onde operou), médico (CRM)
      t.string :provider_name
      t.string :clinic_name
      t.integer :clinic_id
      t.string :doctor_crm
      t.string :procedure_name
      t.string :procedure_type
      t.string :eye
      t.date :surgery_date
      t.string :surgery_hour
      # dinheiro: valor cobrado, custo do prestador, taxa da plataforma, abatimento
      t.decimal :amount, precision: 12, scale: 2
      t.decimal :clinic_price, precision: 12, scale: 2
      t.decimal :profit, precision: 12, scale: 2
      t.decimal :rebate, precision: 12, scale: 2
      t.decimal :paid_amount, precision: 12, scale: 2
      t.datetime :of_created_at
      t.datetime :of_modified_at
      # rastro do tratamento: como casou o paciente e o que fez no card
      t.string :match_via
      t.string :applied_action
      t.datetime :applied_at
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end
    add_index :cevico_oftalmofacil_surgeries, [:account_id, :item_token], unique: true,
              name: 'index_of_surgeries_unique_token'
    add_index :cevico_oftalmofacil_surgeries, [:account_id, :surgery_date]
    add_index :cevico_oftalmofacil_surgeries, [:account_id, :status_kind]
  end
end
