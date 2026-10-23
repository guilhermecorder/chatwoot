# Troca de status da O.S. com as regras da loja: só transições permitidas,
# data de entrega ao marcar "retirou", e o reflexo no card do CRM. Também
# é quem fecha a O.S. como "pronta" quando o último pedido do laboratório chega.
class Otica::OrderStatus
  def self.change!(order, new_status, delivered_at: nil)
    new_status = new_status.to_s
    raise ArgumentError, 'Status inválido.' unless Otica::Order::STATUSES.key?(new_status)
    return order if order.status == new_status

    unless order.can_transition_to?(new_status)
      raise ArgumentError, "#{order.label} está #{Otica::Order::STATUSES[order.status].downcase} e não pode ir para " \
                           "#{Otica::Order::STATUSES[new_status].downcase}."
    end

    attrs = { status: new_status }
    attrs[:delivered_at] = delivered_time(delivered_at) if new_status == 'entregue'
    attrs[:delivered_at] = nil if order.delivered? && new_status != 'entregue'
    order.update!(attrs)
    Otica::CrmBridge.reflect(order)
    order
  end

  # a tela manda só a DATA da retirada: hoje = agora; outro dia = meio-dia
  # daquele dia (em São Paulo), para não aparecer "00:00" no quadro
  def self.delivered_time(value)
    return Time.zone.now if value.blank?

    text = value.to_s
    return Otica::TZ.parse(text) || Time.zone.now unless text.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    date = Date.parse(text)
    date == Otica.today ? Time.zone.now : Otica::TZ.local(date.year, date.month, date.day, 12)
  rescue ArgumentError
    Time.zone.now
  end

  # o laboratório devolveu tudo? então a O.S. está pronta para o cliente
  def self.after_lab_change!(order)
    order.lab_orders.reload
    change!(order, 'pronta') if order.status == 'em_producao' && order.lab_complete?
    order
  end
end
