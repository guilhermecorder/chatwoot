# ESTOQUE (item 68): dashboard próprio dentro do Financeiro (custo parado
# + potencial de lucro + alertas de estoque baixo) e a CONSULTA rápida
# usada na indicação de cirurgia do Espaço do Paciente — tem a lente?
# agenda; não tem? abre PEDIDO vinculado ao card do paciente.
#
# Acesso: o dashboard e o CRUD (com custos) são área financeira (concessão
# :finance). A consulta (lookup) e o pedido a partir da indicação são do
# dia a dia clínico — abertos ao time logado, SEM expor custo/preço.
class Api::V1::Accounts::Crm::StockController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:finance) }, except: [:lookup, :create_order]

  ORDERS_LIMIT = 200

  def show
    order_rows = orders.order(Arel.sql("CASE WHEN status IN ('pendente','encomendado') THEN 0 ELSE 1 END"), id: :desc)
                       .limit(ORDERS_LIMIT).to_a
    # auditoria S4: contatos dos pedidos em UMA query (era 1 por pedido)
    contacts_by_id = Current.account.contacts.where(id: order_rows.filter_map(&:contact_id)).index_by(&:id)
    render json: {
      categories: CevicoStockItem::CATEGORIES,
      order_statuses: CevicoStockOrder::STATUSES,
      summary: build_summary,
      items: items.order(:category, :name, :specification).map { |i| item_json(i) },
      orders: order_rows.map { |o| order_json(o, contacts_by_id) }
    }
  end

  def create_item
    item = items.new(item_params)
    return render json: { error: item.errors.full_messages.first }, status: :unprocessable_entity unless item.save

    render json: item_json(item)
  end

  def update_item
    item = items.find(params[:item_id])
    return render json: { error: item.errors.full_messages.first }, status: :unprocessable_entity unless item.update(item_params)

    render json: item_json(item)
  end

  def delete_item
    items.find(params[:item_id]).destroy!
    head :ok
  end

  # CONSULTA da indicação (aberta ao time): "Catarata — Trifocal" acha a
  # "Lente Trifocal" (basta UM termo bater; mais termos = mais relevante).
  # Devolve só nome/config/quantidade — sem custo nem preço.
  def lookup # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    terms = params[:q].to_s.strip.downcase.split(/[\s—–-]+/).reject { |t| t.length < 3 }.first(6)
    return render json: { matches: [] } if terms.empty?

    scored = items.map do |item|
      haystack = "#{item.name} #{item.specification}".downcase
      [terms.count { |t| haystack.include?(t) }, item]
    end
    matches = scored.select { |score, _i| score.positive? }
                    .sort_by { |score, item| [-score, -item.quantity] }
                    .first(8)
    render json: {
      matches: matches.map do |_score, i|
        { id: i.id, name: i.name, specification: i.specification, quantity: i.quantity, available: i.quantity.positive? }
      end
    }
  end

  # PEDIDO (aberto ao time): nasce da indicação sem estoque — vinculado ao
  # card do paciente (task) com o motivo.
  def create_order
    order = orders.new(order_params.merge(created_by_id: Current.user.id))
    return render json: { error: order.errors.full_messages.first }, status: :unprocessable_entity unless order.save

    render json: order_json(order)
  end

  # mudar status; RECEBIDO soma a quantidade no item do catálogo (se houver).
  # Auditoria S1: transições seguem a máquina do modelo (recebido/cancelado
  # são finais), o status é RELIDO sob trava (duplo clique = no-op) e a
  # soma no estoque acontece dentro da mesma trava.
  def update_order
    order = orders.find(params[:order_id])
    new_status = params[:status].to_s
    return render json: { error: 'Status inválido.' }, status: :unprocessable_entity unless CevicoStockOrder::STATUSES.key?(new_status)

    error = apply_order_transition(order, new_status)
    return render json: { error: error }, status: :unprocessable_entity if error

    render json: order_json(order.reload)
  end

  def delete_order
    orders.find(params[:order_id]).destroy!
    head :ok
  end

  private

  def items
    Current.account.cevico_stock_items
  end

  def orders
    Current.account.cevico_stock_orders
  end

  # devolve mensagem de erro (ou nil no sucesso); roda inteiro sob a trava
  # do pedido para o status relido valer de verdade contra corridas
  def apply_order_transition(order, new_status)
    error = nil
    order.with_lock do
      next if order.status == new_status # repetição (duplo clique) = no-op

      unless CevicoStockOrder::TRANSITIONS.fetch(order.status, []).include?(new_status)
        atual = CevicoStockOrder::STATUSES[order.status].downcase
        error = "Pedido #{atual} é final — não pode virar #{CevicoStockOrder::STATUSES[new_status].downcase}."
        next
      end

      receiving = new_status == 'recebido'
      order.update!(status: new_status, received_at: receiving ? Time.zone.now : order.received_at)
      restock_from(order) if receiving
    end
    error
  end

  # a soma no catálogo também trava o item (duas recepções simultâneas de
  # pedidos diferentes não perdem quantidade)
  def restock_from(order)
    return if order.stock_item.blank?

    order.stock_item.with_lock do
      order.stock_item.update!(quantity: order.stock_item.quantity + order.quantity)
    end
  end

  def item_params # rubocop:disable Metrics/AbcSize
    {
      name: params[:name].to_s.strip[0, 120],
      category: params[:category].to_s.presence || 'lentes',
      specification: params[:specification].to_s.strip[0, 200],
      quantity: params[:quantity].to_i.clamp(0, 999_999),
      min_quantity: params[:min_quantity].to_i.clamp(0, 999_999),
      unit_cost: params[:unit_cost].to_f.round(2),
      sale_price: params[:sale_price].to_f.round(2),
      supplier: params[:supplier].to_s.strip[0, 120],
      notes: params[:notes].to_s.strip[0, 300]
    }
  end

  def order_params # rubocop:disable Metrics/AbcSize
    {
      # auditoria S2: o item TEM que ser da conta — id alheio vira nil
      stock_item_id: params[:stock_item_id].presence && items.find_by(id: params[:stock_item_id])&.id,
      item_name: params[:item_name].to_s.strip[0, 200],
      specification: params[:specification].to_s.strip[0, 200],
      quantity: [params[:quantity].to_i, 1].max,
      reason: params[:reason].to_s.strip[0, 300],
      task_id: params[:task_id].presence,
      contact_id: params[:contact_id].presence
    }
  end

  def build_summary
    all = items.to_a
    {
      items_count: all.size,
      units: all.sum(&:quantity),
      total_cost: all.sum(&:total_cost).round(2),
      potential_revenue: all.sum { |i| (i.quantity * i.sale_price.to_f).round(2) }.round(2),
      # itens de consumo (sem preço de venda) não entram no potencial
      potential_profit: all.sum { |i| i.sale_price.to_f.positive? ? i.potential_profit : 0 }.round(2),
      low_stock: all.count(&:low_stock?),
      open_orders: orders.open_orders.count
    }
  end

  def item_json(item)
    {
      id: item.id,
      name: item.name,
      category: item.category,
      category_label: CevicoStockItem::CATEGORIES[item.category],
      specification: item.specification,
      quantity: item.quantity,
      min_quantity: item.min_quantity,
      low: item.low_stock?,
      unit_cost: item.unit_cost.to_f,
      sale_price: item.sale_price.to_f,
      total_cost: item.total_cost,
      potential_profit: item.potential_profit,
      supplier: item.supplier,
      notes: item.notes
    }
  end

  # contacts_cache (hash id→contato) evita o N+1 na listagem; os endpoints
  # de pedido único seguem com o lookup direto
  def order_json(order, contacts_cache = nil) # rubocop:disable Metrics/MethodLength
    contact = if contacts_cache
                contacts_cache[order.contact_id]
              else
                order.contact_id && Current.account.contacts.find_by(id: order.contact_id)
              end
    {
      id: order.id,
      stock_item_id: order.stock_item_id,
      item_name: order.item_name,
      specification: order.specification,
      quantity: order.quantity,
      reason: order.reason,
      status: order.status,
      status_label: CevicoStockOrder::STATUSES[order.status],
      task_id: order.task_id,
      contact_id: order.contact_id,
      contact_name: contact&.name,
      received_at: order.received_at&.iso8601,
      created_at: order.created_at.iso8601
    }
  end
end
