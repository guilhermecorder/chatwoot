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
      # 🪞 prova virtual
      frame_shapes: ::Otica::Product::FRAME_SHAPES,
      frame_fits: ::Otica::Product::FRAME_FITS,
      face_shapes: ::Otica::Visagismo::FACE_SHAPES,
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

  # 🪞 prova virtual (08/11): foto da armação (de frente, fundo branco/transparente, até 8 MB)
  def photo
    product = products.find(params[:id])
    file = params[:photo]
    return render json: { error: 'Envie a foto da armação.' }, status: :unprocessable_entity if file.blank? || !file.respond_to?(:read)
    return render json: { error: 'A foto precisa ser JPG, PNG ou WEBP.' }, status: :unprocessable_entity unless PHOTO_TYPES.include?(file.content_type.to_s)
    return render json: { error: 'Foto grande demais (até 8 MB).' }, status: :unprocessable_entity if file.size.to_i > PHOTO_MAX_BYTES

    product.photo.attach(file)
    render json: product.reload.as_json_otica
  end

  # 🪞 08/11: FOTOS EM LOTE — cada arquivo com o nome do código do SavWin (ARM-003.jpg,
  # 7891234.png = código de barras, ou o nome exato do produto). Casa pelo sku, depois
  # pelo código de barras, depois pelo nome; devolve o que entrou e o que não achou.
  def photos_bulk # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    files = Array(params[:photos]).select { |f| f.respond_to?(:read) }
    return render json: { error: 'Envie as fotos (nome do arquivo = código do produto).' }, status: :unprocessable_entity if files.empty?

    done = []
    skipped = []
    files.first(200).each do |file|
      stem = File.basename(file.original_filename.to_s, '.*').strip
      product = find_for_photo(stem)
      if product.nil?
        skipped << { arquivo: file.original_filename, motivo: 'produto não encontrado pelo código, código de barras ou nome' }
        next
      end
      unless PHOTO_TYPES.include?(file.content_type.to_s)
        skipped << { arquivo: file.original_filename, motivo: 'precisa ser JPG, PNG ou WEBP' }
        next
      end
      if file.size.to_i > PHOTO_MAX_BYTES
        skipped << { arquivo: file.original_filename, motivo: 'maior que 8 MB' }
        next
      end
      product.photo.attach(file)
      done << { arquivo: file.original_filename, product_id: product.id, produto: product.name }
    end
    render json: { entraram: done, pularam: skipped, total: files.size }
  end

  def delete_photo
    product = products.find(params[:id])
    product.photo.purge_later if product.photo.attached?
    render json: product.reload.as_json_otica.merge(photo_url: nil, try_on_ready: false)
  end

  PHOTO_TYPES = %w[image/jpeg image/png image/webp].freeze

  def find_for_photo(stem)
    return nil if stem.blank?

    scope = products.active
    scope.find_by('LOWER(sku) = ?', stem.downcase) ||
      scope.find_by(barcode: stem) ||
      scope.find_by('LOWER(name) = ?', stem.downcase) ||
      (stem.match?(/\A\d+\z/) ? scope.find_by(id: stem.to_i) : nil)
  end
  PHOTO_MAX_BYTES = 8.megabytes

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
    %w[name brand line model color size sku barcode ncm lens_material lens_treatment notes visagismo_notes].each do |f|
      attrs[f] = params[f].to_s.strip[0, 160] if params.key?(f)
    end
    # 🪞 prova virtual (08/11): formato da armação, público e se entra na prova
    attrs[:frame_shape] = params[:frame_shape].to_s if params.key?(:frame_shape)
    attrs[:frame_fit] = params[:frame_fit].to_s if params.key?(:frame_fit)
    attrs[:try_on] = ActiveModel::Type::Boolean.new.cast(params[:try_on]) if params.key?(:try_on)
    # 💬 venda pelo WhatsApp (08/11): desconto máximo (%) e o jeito de explicar
    attrs[:max_discount_pct] = params[:max_discount_pct].to_s.tr(',', '.').to_f.clamp(0, 90).round(2) if params.key?(:max_discount_pct)
    attrs[:pitch] = params[:pitch].to_s.strip[0, 400] if params.key?(:pitch)
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
