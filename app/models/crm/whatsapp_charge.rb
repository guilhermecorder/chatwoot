# 💸 item 303: a fatura do WhatsApp segundo a própria Meta (pricing_analytics),
# uma linha por dia × número × categoria × tipo de cobrança.
# == Schema Information
#
# Table name: crm_whatsapp_charges
#
#  id           :bigint           not null, primary key
#  category     :string           not null
#  cost         :decimal(12, 4)   default(0.0), not null
#  currency     :string           default("USD"), not null
#  day          :date             not null
#  phone_number :string           default(""), not null
#  pricing_type :string           not null
#  volume       :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  waba_id      :string           not null
#
# Indexes
#
#  idx_crm_wa_charges_unique                         (account_id,waba_id,phone_number,day,category,pricing_type) UNIQUE
#  index_crm_whatsapp_charges_on_account_id          (account_id)
#  index_crm_whatsapp_charges_on_account_id_and_day  (account_id,day)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::WhatsappCharge < ApplicationRecord
  self.table_name = 'crm_whatsapp_charges'

  belongs_to :account

  # o que a Meta manda no status de cada mensagem e no pricing_analytics
  TYPE_REGULAR = 'regular'.freeze                  # cobrada
  TYPE_FREE_WINDOW = 'free_customer_service'.freeze # grátis: dentro das 24h (acaba 01/10/2026)
  TYPE_FREE_AD = 'free_entry_point'.freeze          # grátis: 72h do anúncio Clique-para-WhatsApp

  scope :billable, -> { where(pricing_type: TYPE_REGULAR) }

  validates :waba_id, :day, :category, :pricing_type, presence: true
end
