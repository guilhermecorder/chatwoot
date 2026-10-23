# 👓 A O.S. (venda) da ótica — fase 1. Lista com resumo, ficha completa,
# gravar/alterar, mudar status (reflete no card do CRM), pedido ao
# laboratório e o resumo para o WhatsApp.
# Acesso: nó otica.vendas; quem só tem otica.producao também VÊ as O.S. e
# pode receber do laboratório / marcar pronta / marcar retirada.
class Api::V1::Accounts::Crm::Otica::OrdersController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  LIMIT = 500
  RECENT_DAYS = 90
  VIEW_NODES = %w[otica.vendas otica.producao].freeze

  before_action -> { require_any_node(VIEW_NODES, :view) }, only: [:index, :show, :whatsapp]
  before_action -> { require_any_node(VIEW_NODES, :edit) }, only: [:set_status, :lab_orders]
  before_action :order, only: [:show, :update, :destroy, :set_status, :lab_orders, :whatsapp]

  def index
    render json: {
      statuses: ::Otica::Order::STATUSES,
      payment_methods: ::Otica::Payment::METHODS,
      lab_statuses: ::Otica::LabOrder::STATUSES,
      kinds: ::Otica::Product::KINDS,
      summary: summary,
      orders: listed_orders.map { |o| ::Otica::OrderJson.call(o) }
    }
  end

  def show
    render json: { order: ::Otica::OrderJson.call(order) }
  end

  def create
    created = ::Otica::OrderForm.new(account: Current.account, user: Current.user, params: params).create
    render json: { order: ::Otica::OrderJson.call(created) }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    updated = ::Otica::OrderForm.new(account: Current.account, user: Current.user, params: params).update(order)
    render json: { order: ::Otica::OrderJson.call(updated) }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    unless %w[orcamento cancelada].include?(order.status)
      return render json: { error: 'Só orçamento ou venda cancelada podem ser apagados. Cancele a venda primeiro.' },
                    status: :unprocessable_entity
    end

    order.destroy!
    head :ok
  end

  def set_status
    ::Otica::OrderStatus.change!(order, params[:status], delivered_at: params[:delivered_at].presence)
    render json: { order: ::Otica::OrderJson.call(order.reload) }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # um pedido ao laboratório POR ITEM marcado; a O.S. vai para "em produção"
  def lab_orders # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    item_ids = Array(params[:item_ids]).map(&:to_i)
    items = order.items.where(id: item_ids)
    return render json: { error: 'Marque pelo menos um item para pedir ao laboratório.' }, status: :unprocessable_entity if items.empty?

    supplier = Current.account.otica_suppliers.find_by(id: params[:supplier_id])
    expected = parse_date(params[:expected_on])
    ActiveRecord::Base.transaction do
      items.each do |item|
        next if item.lab_order&.status.in?(%w[pendente enviado recebido])

        order.lab_orders.create!(account: Current.account, order_item: item, supplier: supplier,
                                 status: 'enviado', sent_at: Time.zone.now,
                                 expected_on: expected || default_expected(item, supplier),
                                 cost: Cevico::Money.parse(params[:cost]) || 0.0, notes: params[:notes].to_s.strip[0, 300])
      end
    end
    ::Otica::OrderStatus.change!(order, 'em_producao') if %w[aberta pronta].include?(order.status)
    render json: { order: ::Otica::OrderJson.call(order.reload) }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def whatsapp
    summary_text = ::Otica::WhatsappSummary.new(order, company_name: cevico_company.name)
    render json: { text: summary_text.text, link: summary_text.link }
  end

  private

  def order
    @order ||= Current.account.otica_orders.includes(:contact, :seller, :prescription, :payments, :second_pairs,
                                                     items: :lab_order, lab_orders: [:supplier, :order_item]).find(params[:id])
  end

  def require_any_node(nodes, level)
    return if nodes.any? { |n| cevico_access.can?(n, level) }

    render json: { error: cevico_denied_message(nodes.first, level) }, status: :forbidden
  end

  def listed_orders # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    scope = Current.account.otica_orders.includes(:contact, :seller, :prescription, :payments, :second_pairs,
                                                  items: :lab_order, lab_orders: [:supplier, :order_item])
    scope = if params[:status].present? && ::Otica::Order::STATUSES.key?(params[:status].to_s)
              scope.where(status: params[:status].to_s)
            elsif params[:from].present? || params[:to].present?
              scope.sold_between(parse_date(params[:from]) || 20.years.ago.to_date, parse_date(params[:to]) || Otica.today)
            else
              scope.where(status: ::Otica::Order::OPEN_STATUSES).or(scope.where(sold_on: (Otica.today - RECENT_DAYS)..))
            end
    if params[:q].present?
      q = params[:q].to_s.strip
      digits = q.gsub(/\D/, '')
      scope = scope.joins(:contact).where(
        'contacts.name ILIKE :like OR otica_orders.number::text = :num ' \
        "OR (:digits <> '' AND regexp_replace(COALESCE(contacts.phone_number,''), '\\D', '', 'g') LIKE :tel)",
        like: "%#{q}%", num: q, digits: digits, tel: "%#{digits}%"
      )
    end
    scope.order(sold_on: :desc, id: :desc).limit(LIMIT)
  end

  def summary # rubocop:disable Metrics/AbcSize
    all = Current.account.otica_orders
    today = Otica.today
    month = all.sold_between(today.beginning_of_month, today).where.not(status: %w[orcamento cancelada devolvida])
    delivered_month = all.where(status: 'entregue', delivered_at: today.beginning_of_month.in_time_zone(TZ).beginning_of_day..).count
    sold = month.sum(:net).to_f.round(2)
    {
      abertas: all.where(status: 'aberta').count,
      em_producao: all.where(status: 'em_producao').count,
      prontas: all.where(status: 'pronta').count,
      atrasadas: all.open_orders.where('due_on < ?', today).count,
      entregues_mes: delivered_month,
      vendido_mes: sold,
      vendas_mes: month.count,
      ticket_mes: month.count.positive? ? (sold / month.count).round(2) : 0.0
    }
  end

  def default_expected(item, supplier)
    days = item.product&.lab_days.to_i
    days = supplier&.lab_days.to_i if days.zero?
    days = 7 if days.zero?
    Otica.today + days
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
