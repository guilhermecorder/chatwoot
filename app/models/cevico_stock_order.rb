# Um PEDIDO de estoque: nasce quando falta um item (em geral na indicação
# de cirurgia de um paciente — o pedido fica vinculado ao card do CRM com
# o motivo). Fluxo: pendente → encomendado → recebido (entra no estoque)
# ou cancelado.
# == Schema Information
#
# Table name: cevico_stock_orders
#
#  id            :bigint           not null, primary key
#  item_name     :string           not null
#  quantity      :integer          default(1), not null
#  reason        :string           default("")
#  received_at   :datetime
#  specification :string           default("")
#  status        :string           default("pendente"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  contact_id    :integer
#  created_by_id :integer
#  stock_item_id :bigint
#  task_id       :integer
#
# Indexes
#
#  index_cevico_stock_orders_on_account_id             (account_id)
#  index_cevico_stock_orders_on_account_id_and_status  (account_id,status)
#  index_cevico_stock_orders_on_stock_item_id          (stock_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (stock_item_id => cevico_stock_items.id)
#
class CevicoStockOrder < ApplicationRecord
  belongs_to :account
  belongs_to :stock_item, class_name: 'CevicoStockItem', optional: true

  STATUSES = {
    'pendente' => 'Pendente',
    'encomendado' => 'Encomendado',
    'recebido' => 'Recebido',
    'cancelado' => 'Cancelado'
  }.freeze
  OPEN_STATUSES = %w[pendente encomendado].freeze

  # máquina de transições (auditoria 19/07, achado S1): recebido e
  # cancelado são FINAIS — sem ciclo cancelar→receber que duplicava a
  # soma no estoque. Repetir o mesmo status é tratado como no-op fora.
  TRANSITIONS = {
    'pendente' => %w[encomendado recebido cancelado],
    'encomendado' => %w[recebido cancelado],
    'recebido' => [],
    'cancelado' => []
  }.freeze

  validates :item_name, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :quantity, numericality: { greater_than: 0, only_integer: true }

  scope :open_orders, -> { where(status: OPEN_STATUSES) }
end
