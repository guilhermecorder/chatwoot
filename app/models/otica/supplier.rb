# Fornecedor da ótica. kind 'lab' = laboratório (quem monta a lente), com
# prazo padrão em dias; 'fornecedor' = armações, acessórios etc.
# == Schema Information
#
# Table name: otica_suppliers
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  email      :string           default("")
#  kind       :string           default("fornecedor"), not null
#  lab_days   :integer          default(0), not null
#  name       :string           not null
#  notes      :string           default("")
#  phone      :string           default("")
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_otica_suppliers_on_account_id           (account_id)
#  index_otica_suppliers_on_account_id_and_kind  (account_id,kind)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Otica::Supplier < ApplicationRecord
  belongs_to :account
  has_many :products, class_name: 'Otica::Product', dependent: :nullify, inverse_of: :supplier
  has_many :lab_orders, class_name: 'Otica::LabOrder', dependent: :nullify, inverse_of: :supplier

  KINDS = { 'lab' => 'Laboratório', 'fornecedor' => 'Fornecedor' }.freeze

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :lab_days, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  scope :active, -> { where(active: true) }
  scope :labs, -> { where(kind: 'lab') }

  def lab?
    kind == 'lab'
  end

  def as_json_otica
    { id: id, name: name, kind: kind, kind_label: KINDS[kind], phone: phone, email: email,
      lab_days: lab_days, notes: notes, active: active }
  end
end
