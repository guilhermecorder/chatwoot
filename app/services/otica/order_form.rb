# Monta/atualiza a O.S. a partir do que a tela mandou: acha ou cria o
# cliente (contato) pelo telefone, grava a receita, os itens (preço
# congelado) e os pagamentos, recalcula os totais e reflete no card do CRM.
# Erros de regra viram ArgumentError com a frase para a equipe.
class Otica::OrderForm
  CREATE_STATUSES = %w[orcamento aberta].freeze

  def initialize(account:, user:, params:)
    @account = account
    @user = user
    # aceita ActionController::Parameters (controller) ou Hash (rake/specs)
    raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    @p = raw.with_indifferent_access
  end

  def create
    order = nil
    ActiveRecord::Base.transaction do
      contact = resolve_contact!
      status = @p[:status].to_s.presence || 'aberta'
      raise ArgumentError, 'Uma venda nova nasce como orçamento ou aberta.' unless CREATE_STATUSES.include?(status)

      order = @account.otica_orders.new(order_attributes.merge(contact: contact, status: status, created_by_id: @user&.id))
      order.sold_on ||= Otica.today
      order.prescription = build_prescription(contact) if prescription_given?
      order.save!
      replace_items!(order)
      replace_payments!(order)
      order.recalculate!
    end
    Otica::CrmBridge.reflect(order) if order.status == 'aberta'
    order.reload
  end

  def update(order) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    was = order.status
    ActiveRecord::Base.transaction do
      order.assign_attributes(order_attributes)
      if @p.key?(:status) && @p[:status].to_s != was
        new_status = @p[:status].to_s
        raise ArgumentError, 'Para mudar o status use o botão de status.' unless was == 'orcamento' && new_status == 'aberta'

        order.status = new_status
      end
      if prescription_given?
        order.prescription ||= Otica::Prescription.new(account: @account, contact: order.contact)
        apply_prescription(order.prescription)
        order.prescription.save!
      end
      order.save!
      replace_items!(order) if @p.key?(:items)
      replace_payments!(order) if @p.key?(:payments)
      order.recalculate!
    end
    Otica::CrmBridge.reflect(order) if was == 'orcamento' && order.status == 'aberta'
    order.reload
  end

  private

  def order_attributes # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    attrs = {}
    attrs[:seller_id] = @account.users.find_by(id: @p[:seller_id])&.id if @p.key?(:seller_id)
    attrs[:doctor_name] = @p[:doctor_name].to_s.strip[0, 120] if @p.key?(:doctor_name)
    attrs[:sold_on] = parse_date(@p[:sold_on]) if @p[:sold_on].present?
    attrs[:due_on] = parse_date(@p[:due_on]) if @p.key?(:due_on)
    attrs[:discount] = Cevico::Money.parse(@p[:discount]) || 0.0 if @p.key?(:discount)
    attrs[:notes] = @p[:notes].to_s.strip[0, 2000] if @p.key?(:notes)
    if @p.key?(:second_pair_of_id)
      attrs[:second_pair_of_id] = @p[:second_pair_of_id].presence && @account.otica_orders.find_by(id: @p[:second_pair_of_id])&.id
    end
    attrs
  end

  # cliente: id de um contato da conta, ou nome + telefone (acha pelo
  # telefone com a mesma régua da Agenda; se não existe, cria)
  def resolve_contact! # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    if @p[:contact_id].present?
      contact = @account.contacts.find_by(id: @p[:contact_id])
      raise ArgumentError, 'Cliente não encontrado nesta conta.' if contact.nil?

      return contact
    end

    raw = (@p[:contact] || {}).to_h.with_indifferent_access
    name = raw[:name].to_s.strip[0, 120]
    phone = Crm::AppointmentOrigin.normalize_phone(raw[:phone_number])
    raise ArgumentError, 'Informe o cliente (nome e telefone com DDD).' if name.blank? || phone.nil?

    existing = Task.match_contact(@account, phone)
    return existing if existing

    @account.contacts.create!(name: name, phone_number: phone, additional_attributes: { 'origem' => 'loja' })
  rescue ActiveRecord::RecordInvalid
    Task.match_contact(@account, phone) || raise(ArgumentError, 'Não consegui cadastrar o cliente com esse telefone.')
  end

  def prescription_given?
    raw = @p[:prescription]
    raw.present? && raw.to_h.values.flatten.any? { |v| v.is_a?(Hash) ? v.values.any?(&:present?) : v.present? }
  end

  def build_prescription(contact)
    rx = Otica::Prescription.new(account: @account, contact: contact)
    apply_prescription(rx)
    rx
  end

  def apply_prescription(rx) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/MethodParameterName
    raw = @p[:prescription].to_h.with_indifferent_access
    rx.doctor_name = raw[:doctor_name].to_s.strip[0, 120] if raw.key?(:doctor_name)
    rx.prescribed_on = parse_date(raw[:prescribed_on]) if raw.key?(:prescribed_on)
    rx.valid_until = parse_date(raw[:valid_until]) if raw.key?(:valid_until)
    rx.notes = raw[:notes].to_s.strip[0, 500] if raw.key?(:notes)
    rx.photo_url = raw[:photo_url].to_s.strip[0, 500] if raw.key?(:photo_url)
    Otica::Prescription::EYES.each do |eye|
      eye_raw = (raw[eye] || {}).to_h.with_indifferent_access
      Otica::Prescription::FIELDS.each do |field|
        next unless eye_raw.key?(field)

        value = eye_raw[field]
        rx.public_send("#{eye}_#{field}=", field == 'axis' ? value.presence&.to_i : parse_decimal(value))
      end
    end
  end

  def replace_items!(order) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows = Array(@p[:items]).map { |r| r.to_h.with_indifferent_access }
    raise ArgumentError, 'A venda precisa de pelo menos um item.' if rows.empty? && order.status != 'orcamento'

    order.items.destroy_all
    rows.each do |row|
      product = row[:product_id].present? ? @account.otica_products.find_by(id: row[:product_id]) : nil
      order.items.create!(
        account: @account, product: product,
        kind: row[:kind].to_s.presence || product&.kind || 'outro',
        description: row[:description].to_s.strip[0, 200].presence || product&.name.to_s,
        quantity: [row[:quantity].to_i, 1].max,
        unit_price: row.key?(:unit_price) && row[:unit_price].present? ? (Cevico::Money.parse(row[:unit_price]) || 0.0) : product&.price.to_f,
        discount: Cevico::Money.parse(row[:discount]) || 0.0
      )
    end
  end

  def replace_payments!(order)
    rows = Array(@p[:payments]).map { |r| r.to_h.with_indifferent_access }
    order.payments.destroy_all
    rows.each do |row|
      amount = Cevico::Money.parse(row[:amount]) || 0.0
      next unless amount.positive?

      order.payments.create!(account: @account, method: row[:method].to_s.presence || 'pix',
                             installments: [row[:installments].to_i, 1].max, amount: amount,
                             paid_on: parse_date(row[:paid_on]), notes: row[:notes].to_s.strip[0, 200])
    end
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_decimal(value)
    return nil if value.blank?

    Cevico::Money.parse(value.to_s.tr('+', ''))
  end
end
