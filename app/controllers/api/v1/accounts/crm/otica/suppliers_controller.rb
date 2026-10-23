# 👓 FORNECEDORES E LABORATÓRIOS da ótica (fase 1). Nó otica.produtos.
class Api::V1::Accounts::Crm::Otica::SuppliersController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  def index
    render json: { supplier_kinds: ::Otica::Supplier::KINDS, suppliers: suppliers.order(:kind, :name).map(&:as_json_otica) }
  end

  def create
    supplier = suppliers.new(supplier_params)
    return render json: { error: supplier.errors.full_messages.first }, status: :unprocessable_entity unless supplier.save

    render json: supplier.as_json_otica
  end

  def update
    supplier = suppliers.find(params[:id])
    return render json: { error: supplier.errors.full_messages.first }, status: :unprocessable_entity unless supplier.update(supplier_params)

    render json: supplier.as_json_otica
  end

  def destroy
    supplier = suppliers.find(params[:id])
    if supplier.lab_orders.exists? || supplier.products.exists?
      supplier.update!(active: false)
      return render json: supplier.as_json_otica.merge(deactivated: true)
    end

    supplier.destroy!
    head :ok
  end

  private

  def suppliers
    Current.account.otica_suppliers
  end

  def supplier_params # rubocop:disable Metrics/AbcSize
    attrs = {}
    %w[name phone email notes].each { |f| attrs[f] = params[f].to_s.strip[0, 160] if params.key?(f) }
    attrs[:kind] = params[:kind].to_s if ::Otica::Supplier::KINDS.key?(params[:kind].to_s)
    attrs[:lab_days] = params[:lab_days].to_i.clamp(0, 365) if params.key?(:lab_days)
    attrs[:active] = ActiveModel::Type::Boolean.new.cast(params[:active]) if params.key?(:active)
    attrs
  end
end
