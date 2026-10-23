# A O.S. (venda) da ótica: cliente (contato do Chatwoot), vendedor, receita,
# itens, pagamentos, previsão e data de entrega. O status caminha
# orçamento → aberta → em produção → pronta → entregue (ou cancelada /
# devolvida) e cada passo reflete no card do cliente no CRM
# (Otica::CrmBridge), que por sua vez dispara a Jornada já montada.
# == Schema Information
#
# Table name: otica_orders
#
#  id                :bigint           not null, primary key
#  delivered_at      :datetime
#  discount          :decimal(12, 2)   default(0.0), not null
#  doctor_name       :string           default("")
#  due_on            :date
#  gross             :decimal(12, 2)   default(0.0), not null
#  net               :decimal(12, 2)   default(0.0), not null
#  notes             :text
#  number            :integer          not null
#  sold_on           :date             not null
#  status            :string           default("aberta"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  contact_id        :bigint           not null
#  created_by_id     :integer
#  crm_contact_id    :integer
#  prescription_id   :bigint
#  second_pair_of_id :bigint
#  seller_id         :bigint
#
# Indexes
#
#  index_otica_orders_on_account_id              (account_id)
#  index_otica_orders_on_account_id_and_number   (account_id,number) UNIQUE
#  index_otica_orders_on_account_id_and_sold_on  (account_id,sold_on)
#  index_otica_orders_on_account_id_and_status   (account_id,status)
#  index_otica_orders_on_contact_id              (contact_id)
#  index_otica_orders_on_prescription_id         (prescription_id)
#  index_otica_orders_on_second_pair_of_id       (second_pair_of_id)
#  index_otica_orders_on_seller_id               (seller_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (prescription_id => otica_prescriptions.id) ON DELETE => nullify
#  fk_rails_...  (second_pair_of_id => otica_orders.id) ON DELETE => nullify
#  fk_rails_...  (seller_id => users.id) ON DELETE => nullify
#
class Otica::Order < ApplicationRecord
  belongs_to :account
  belongs_to :contact, class_name: '::Contact'
  belongs_to :seller, class_name: 'User', optional: true
  belongs_to :prescription, class_name: 'Otica::Prescription', optional: true, inverse_of: :orders
  belongs_to :second_pair_of, class_name: 'Otica::Order', optional: true, inverse_of: :second_pairs
  has_many :second_pairs, class_name: 'Otica::Order', foreign_key: :second_pair_of_id, dependent: :nullify, inverse_of: :second_pair_of
  has_many :items, class_name: 'Otica::OrderItem', dependent: :destroy, inverse_of: :order
  has_many :lab_orders, class_name: 'Otica::LabOrder', dependent: :destroy, inverse_of: :order
  has_many :payments, class_name: 'Otica::Payment', dependent: :destroy, inverse_of: :order

  STATUSES = {
    'orcamento' => 'Orçamento',
    'aberta' => 'Aberta',
    'em_producao' => 'Em produção',
    'pronta' => 'Pronta',
    'entregue' => 'Entregue',
    'cancelada' => 'Cancelada',
    'devolvida' => 'Devolvida'
  }.freeze
  OPEN_STATUSES = %w[aberta em_producao pronta].freeze
  FINAL_STATUSES = %w[cancelada devolvida].freeze
  # de onde se pode ir para onde (entregue pode voltar para pronta se marcou errado)
  TRANSITIONS = {
    'orcamento' => %w[aberta cancelada],
    'aberta' => %w[em_producao pronta entregue cancelada],
    'em_producao' => %w[pronta entregue cancelada aberta],
    'pronta' => %w[entregue em_producao cancelada],
    'entregue' => %w[devolvida pronta],
    'cancelada' => %w[aberta],
    'devolvida' => []
  }.freeze

  before_validation :assign_number, on: :create
  validates :status, inclusion: { in: STATUSES.keys }
  validates :number, presence: true, uniqueness: { scope: :account_id }
  validates :sold_on, presence: true
  validates :discount, numericality: { greater_than_or_equal_to: 0 }

  scope :open_orders, -> { where(status: OPEN_STATUSES) }
  scope :sold_between, ->(from, to) { where(sold_on: from..to) }

  def open?
    OPEN_STATUSES.include?(status)
  end

  def delivered?
    status == 'entregue'
  end

  # atrasada = passou da previsão e o cliente ainda não retirou
  def late?(today = Otica.today)
    due_on.present? && due_on < today && open?
  end

  def can_transition_to?(new_status)
    TRANSITIONS.fetch(status, []).include?(new_status)
  end

  # bruto = soma dos itens (já com o desconto de cada item); líquido = bruto − desconto da O.S.
  def recalculate!
    items.reload
    gross_value = items.sum { |i| i.total.to_f }.round(2)
    net_value = [gross_value - discount.to_f, 0].max.round(2)
    update_columns(gross: gross_value, net: net_value, updated_at: Time.zone.now) # rubocop:disable Rails/SkipsModelValidations
  end

  def paid
    payments.sum { |p| p.amount.to_f }.round(2)
  end

  def balance
    (net.to_f - paid).round(2)
  end

  # todos os pedidos ao laboratório chegaram (e há pelo menos um)?
  def lab_complete?
    live = lab_orders.reject { |l| l.status == 'cancelado' }
    live.any? && live.all? { |l| l.status == 'recebido' }
  end

  def label
    "O.S. #{number}"
  end

  private

  # nº sequencial por conta (uma loja; a numeração é a da conta)
  def assign_number
    return if number.present? || account.nil?

    self.number = (Otica::Order.where(account_id: account_id).maximum(:number) || 0) + 1
  end
end
