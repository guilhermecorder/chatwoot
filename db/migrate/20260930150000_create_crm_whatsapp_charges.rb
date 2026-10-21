# 💸 item 303 (30/09): GASTO DO WHATSAPP. A Meta passa a cobrar TODA mensagem
# em 01/10/2026 (inclusive as respostas dentro das 24h). Esta tabela guarda a
# "fatura" que a própria Meta informa (pricing_analytics): uma linha por
# dia × número × categoria × tipo de cobrança, com volume e custo na moeda
# da conta. A atribuição por mensagem (robô × equipe × lembrete) fica no
# additional_attributes da própria mensagem (cevico_wa_billing).
class CreateCrmWhatsappCharges < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_whatsapp_charges do |t|
      t.references :account, null: false, foreign_key: true
      t.string :waba_id, null: false
      t.string :phone_number, null: false, default: ''
      t.date :day, null: false
      t.string :category, null: false # marketing | utility | authentication | service | …
      t.string :pricing_type, null: false # regular | free_customer_service | free_entry_point
      t.integer :volume, null: false, default: 0
      t.decimal :cost, precision: 12, scale: 4, null: false, default: 0
      t.string :currency, null: false, default: 'USD'
      t.timestamps
    end
    add_index :crm_whatsapp_charges, %i[account_id day]
    add_index :crm_whatsapp_charges, %i[account_id waba_id phone_number day category pricing_type],
              unique: true, name: 'idx_crm_wa_charges_unique'
  end
end
