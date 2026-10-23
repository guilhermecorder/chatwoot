# 👓 PEDIDO AO LABORATÓRIO (fase 1): mudar status (enviado / chegou /
# cancelado), previsão e custo. Quando o último chega, a O.S. vira pronta.
# Acesso: otica.producao ou otica.vendas (editar).
class Api::V1::Accounts::Crm::Otica::LabOrdersController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  EDIT_NODES = %w[otica.producao otica.vendas].freeze

  before_action -> { require_any_node(EDIT_NODES, :edit) }

  def update # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    lab_order = Current.account.otica_lab_orders.find(params[:id])
    attrs = {}
    if params[:status].present?
      new_status = params[:status].to_s
      return render json: { error: 'Status inválido.' }, status: :unprocessable_entity unless ::Otica::LabOrder::STATUSES.key?(new_status)

      if new_status != lab_order.status && ::Otica::LabOrder::TRANSITIONS.fetch(lab_order.status, []).exclude?(new_status)
        return render json: { error: "Pedido #{::Otica::LabOrder::STATUSES[lab_order.status].downcase} não pode virar " \
                                     "#{::Otica::LabOrder::STATUSES[new_status].downcase}." }, status: :unprocessable_entity
      end
      attrs[:status] = new_status
      attrs[:sent_at] = Time.zone.now if new_status == 'enviado' && lab_order.sent_at.nil?
      attrs[:received_at] = (parse_time(params[:received_at]) || Time.zone.now) if new_status == 'recebido'
      attrs[:received_at] = nil if new_status != 'recebido'
    end
    attrs[:expected_on] = parse_date(params[:expected_on]) if params.key?(:expected_on)
    attrs[:cost] = Cevico::Money.parse(params[:cost]) || 0.0 if params.key?(:cost)
    attrs[:notes] = params[:notes].to_s.strip[0, 300] if params.key?(:notes)
    attrs[:supplier_id] = Current.account.otica_suppliers.find_by(id: params[:supplier_id])&.id if params.key?(:supplier_id)
    lab_order.update!(attrs)
    ::Otica::OrderStatus.after_lab_change!(lab_order.order)
    render json: { order: ::Otica::OrderJson.call(lab_order.order.reload) }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def require_any_node(nodes, level)
    return if nodes.any? { |n| cevico_access.can?(n, level) }

    render json: { error: cevico_denied_message(nodes.first, level) }, status: :forbidden
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
