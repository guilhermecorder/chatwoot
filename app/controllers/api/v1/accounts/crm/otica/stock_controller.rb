# 📦 ESTOQUE da ótica (fase 2): visão (cobertura, encalhados), livro de
# movimentações, movimentação manual, inventário e compras (XML da NF-e ou
# manual). Nó otica.produtos (ver = consulta; editar = movimenta).
class Api::V1::Accounts::Crm::Otica::StockController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  MOVES_LIMIT = 500
  RECENT_MOVES = 30

  def show
    report = ::Otica::StockReport.new(Current.account, days: params[:days].presence || 90).call
    render json: {
      move_kinds: ::Otica::StockMove::KINDS, move_origins: ::Otica::StockMove::ORIGINS,
      purchase_statuses: ::Otica::Purchase::STATUSES, kinds: ::Otica::Product::KINDS,
      summary: report[:summary], rows: report[:rows],
      recent_moves: moves_scope.recent.limit(RECENT_MOVES).map(&:as_json_otica)
    }
  end

  def moves # rubocop:disable Metrics/AbcSize
    scope = moves_scope
    scope = scope.where(product_id: params[:product_id]) if params[:product_id].present?
    scope = scope.where(origin: params[:origin]) if ::Otica::StockMove::ORIGINS.key?(params[:origin].to_s)
    scope = scope.where(created_at: parse_date(params[:from]).in_time_zone(::Otica::TZ).beginning_of_day..) if parse_date(params[:from])
    scope = scope.where(created_at: ..parse_date(params[:to]).in_time_zone(::Otica::TZ).end_of_day) if parse_date(params[:to])
    render json: { moves: scope.recent.limit(MOVES_LIMIT).map(&:as_json_otica) }
  end

  def create_move
    product = Current.account.otica_products.find(params[:product_id])
    move = ::Otica::StockLedger.record!(product: product, kind: params[:kind].to_s, quantity: params[:quantity].to_i,
                                        origin: 'manual', unit_cost: Cevico::Money.parse(params[:unit_cost]),
                                        notes: params[:notes].to_s, user: Current.user)
    render json: { move: move&.as_json_otica, product: product.reload.as_json_otica }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # contagem: cada linha diferente do saldo vira ajuste de inventário
  def inventory # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows = Array(params[:rows]).map { |r| r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r.to_h }
    adjusted = []
    unchanged = 0
    rows.each do |row|
      next if row['counted'].blank?

      product = Current.account.otica_products.find_by(id: row['product_id'])
      next if product.nil?

      move = ::Otica::StockLedger.set_quantity!(product, row['counted'].to_i, origin: 'inventario', user: Current.user,
                                                                              notes: params[:notes].to_s.presence || 'contagem de inventário')
      move ? adjusted << move : unchanged += 1
    end
    render json: { adjusted: adjusted.size, unchanged: unchanged, moves: adjusted.map(&:as_json_otica) }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def purchases
    render json: { purchases: Current.account.otica_purchases.includes(:supplier, items: :product).order(id: :desc).limit(200).map(&:as_json_otica) }
  end

  def preview_xml
    render json: ::Otica::NfeXmlImport.new(Current.account, params[:xml]).call
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create_purchase
    purchase = ::Otica::Purchases.create!(account: Current.account, user: Current.user, params: params)
    render json: { purchase: purchase.as_json_otica }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def receive_purchase
    purchase = Current.account.otica_purchases.find(params[:id])
    ::Otica::Purchases.receive!(purchase, user: Current.user)
    render json: { purchase: purchase.reload.as_json_otica }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def delete_purchase
    purchase = Current.account.otica_purchases.find(params[:id])
    unless purchase.status == 'rascunho'
      return render json: { error: 'Só uma compra ainda em conferência pode ser apagada.' },
                    status: :unprocessable_entity
    end

    purchase.destroy!
    head :ok
  end

  private

  def moves_scope
    Current.account.otica_stock_moves.includes(:product, :reference)
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
