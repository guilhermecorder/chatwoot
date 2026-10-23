# 👓 PRODUTOS DA ÓTICA (fase 1): lista com grade, saldo, custo e preço;
# cadastro; importação do CSV do SavWin. Nó de acesso otica.produtos
# (ver = consulta; editar = cadastra/importa).
class Api::V1::Accounts::Crm::Otica::ProductsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  LIMIT = 2000

  def index # rubocop:disable Metrics/AbcSize
    scope = products
    scope = scope.where(kind: params[:kind]) if ::Otica::Product::KINDS.key?(params[:kind].to_s)
    scope = scope.active unless params[:active].to_s == 'all'
    scope = scope.where(active: false) if params[:active].to_s == '0'
    scope = scope.search(params[:q]) if params[:q].present?
    rows = scope.includes(:supplier).order(:kind, :brand, :model, :color, :size).limit(LIMIT)
    render json: {
      kinds: ::Otica::Product::KINDS,
      lens_types: ::Otica::Product::LENS_TYPES,
      supplier_kinds: ::Otica::Supplier::KINDS,
      summary: summary,
      products: rows.map(&:as_json_otica),
      suppliers: Current.account.otica_suppliers.order(:kind, :name).map(&:as_json_otica)
    }
  end

  # 📦 fase 2: o saldo digitado vira movimentação (cadastro / ajuste manual)
  def create
    attrs = product_params
    quantity = attrs.delete(:quantity)
    product = products.new(attrs)
    return render json: { error: product.errors.full_messages.first }, status: :unprocessable_entity unless product.save

    ::Otica::StockLedger.set_quantity!(product, quantity, origin: 'cadastro', user: Current.user) if quantity.to_i.positive?
    render json: product.reload.as_json_otica
  end

  def update
    product = products.find(params[:id])
    attrs = product_params
    quantity = attrs.delete(:quantity)
    return render json: { error: product.errors.full_messages.first }, status: :unprocessable_entity unless product.update(attrs)

    unless quantity.nil?
      ::Otica::StockLedger.set_quantity!(product, quantity, origin: 'manual', notes: 'saldo alterado no cadastro',
                                                            user: Current.user)
    end
    render json: product.reload.as_json_otica
  end

  def destroy
    product = products.find(params[:id])
    # vendido alguma vez? fica no histórico — só desativa
    if product.order_items.exists?
      product.update!(active: false)
      return render json: product.as_json_otica.merge(deactivated: true)
    end

    product.destroy!
    head :ok
  end

  def import_csv
    csv = params[:csv].to_s
    return render json: { error: 'Envie o conteúdo do arquivo CSV.' }, status: :unprocessable_entity if csv.blank?

    render json: ::Otica::CsvImport.new(Current.account, csv).call.result
  end

  private

  def products
    Current.account.otica_products
  end

  def summary
    all = products.active.to_a
    {
      count: products.count, active: all.size, units: all.sum(&:quantity),
      total_cost: all.sum { |p| p.quantity * p.cost.to_f }.round(2),
      low_stock: all.count(&:low_stock?)
    }
  end

  def product_params # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    attrs = {}
    %w[name brand line model color size sku barcode ncm lens_material lens_treatment notes].each do |f|
      attrs[f] = params[f].to_s.strip[0, 160] if params.key?(f)
    end
    attrs[:kind] = params[:kind].to_s if ::Otica::Product::KINDS.key?(params[:kind].to_s)
    attrs[:lens_type] = params[:lens_type].to_s if params.key?(:lens_type)
    attrs[:cost] = Cevico::Money.parse(params[:cost]) || 0.0 if params.key?(:cost)
    attrs[:list_price] = Cevico::Money.parse(params[:list_price]) || 0.0 if params.key?(:list_price)
    attrs[:promo_price] = Cevico::Money.parse(params[:promo_price]) if params.key?(:promo_price)
    attrs[:promo_until] = (Date.parse(params[:promo_until].to_s) rescue nil) if params.key?(:promo_until) # rubocop:disable Style/RescueModifier
    attrs[:quantity] = params[:quantity].to_i.clamp(0, 999_999) if params.key?(:quantity)
    attrs[:min_quantity] = params[:min_quantity].to_i.clamp(0, 999_999) if params.key?(:min_quantity)
    attrs[:lab_days] = params[:lab_days].to_i.clamp(0, 365) if params.key?(:lab_days)
    attrs[:active] = ActiveModel::Type::Boolean.new.cast(params[:active]) if params.key?(:active)
    if params.key?(:supplier_id)
      attrs[:supplier_id] =
        params[:supplier_id].presence && Current.account.otica_suppliers.find_by(id: params[:supplier_id])&.id
    end
    attrs
  end
end
