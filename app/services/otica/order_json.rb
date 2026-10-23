# A O.S. como a tela lê (contrato em OTICA/docs/FASE-1-API.md).
module Otica::OrderJson
  def self.call(order) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    contact = order.contact
    {
      id: order.id, number: order.number, status: order.status, status_label: Otica::Order::STATUSES[order.status],
      late: order.late?,
      contact: { id: contact.id, name: contact.name, phone_number: contact.phone_number },
      seller: order.seller ? { id: order.seller.id, name: order.seller.name } : nil,
      doctor_name: order.doctor_name,
      sold_on: order.sold_on&.iso8601, due_on: order.due_on&.iso8601, delivered_at: order.delivered_at&.iso8601,
      gross: order.gross.to_f, discount: order.discount.to_f, net: order.net.to_f, paid: order.paid, balance: order.balance,
      notes: order.notes,
      second_pair_of_id: order.second_pair_of_id,
      second_pairs: order.second_pairs.map { |o| { id: o.id, number: o.number } },
      crm_card: Otica::CrmBridge.card_json(order),
      prescription: order.prescription&.as_json_otica,
      items: order.items.order(:id).map(&:as_json_otica),
      payments: order.payments.order(:id).map(&:as_json_otica),
      lab_orders: order.lab_orders.order(:id).map(&:as_json_otica),
      created_at: order.created_at.iso8601, updated_at: order.updated_at.iso8601
    }
  end
end
