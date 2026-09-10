# Espelho de UMA cirurgia do OftalmoFácil (item 157) — ver a migration.
# resultado = o que sobra pra CEVICO: valor cobrado − custo do prestador −
# taxa da plataforma (fórmula do split lida no código do OftalmoFácil).
# == Schema Information
#
# Table name: cevico_oftalmofacil_surgeries
#
#  id             :bigint           not null, primary key
#  amount         :decimal(12, 2)
#  applied_action :string
#  applied_at     :datetime
#  clinic_name    :string
#  clinic_price   :decimal(12, 2)
#  doctor_crm     :string
#  eye            :string
#  item_token     :string           not null
#  match_via      :string
#  of_created_at  :datetime
#  of_modified_at :datetime
#  paid_amount    :decimal(12, 2)
#  patient_cpf    :string
#  patient_email  :string
#  patient_name   :string
#  patient_phone  :string
#  procedure_name :string
#  procedure_type :string
#  profit         :decimal(12, 2)
#  provider_name  :string
#  raw            :jsonb            not null
#  rebate         :decimal(12, 2)
#  status_kind    :string           default("outro"), not null
#  status_label   :string
#  surgery_date   :date
#  surgery_hour   :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  clinic_id      :integer
#  contact_id     :bigint
#  item_id        :integer
#  scheduling_id  :integer
#  status_id      :string
#
# Indexes
#
#  idx_on_account_id_status_kind_028c0b09a6           (account_id,status_kind)
#  idx_on_account_id_surgery_date_a7392a9e19          (account_id,surgery_date)
#  index_cevico_oftalmofacil_surgeries_on_contact_id  (contact_id)
#  index_of_surgeries_unique_token                    (account_id,item_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#
class Crm::OftalmofacilSurgery < ApplicationRecord
  self.table_name = 'cevico_oftalmofacil_surgeries'

  belongs_to :account
  belongs_to :contact, class_name: '::Contact', optional: true

  KINDS = %w[agendada realizada cancelada ausente aguardando_pagamento outro].freeze

  scope :in_period, ->(from, to) { where(surgery_date: from..to) }
  scope :realizadas, -> { where(status_kind: 'realizada') }
  scope :faturaveis, -> { where(status_kind: %w[agendada realizada aguardando_pagamento]) }

  def resultado
    amount.to_f - clinic_price.to_f - profit.to_f
  end

  # rótulo humano da classificação
  def status_kind_label
    {
      'agendada' => 'Agendada', 'realizada' => 'Realizada', 'cancelada' => 'Cancelada',
      'ausente' => 'Não compareceu', 'aguardando_pagamento' => 'Aguardando pagamento'
    }[status_kind] || status_label.presence || 'Outro'
  end
end
