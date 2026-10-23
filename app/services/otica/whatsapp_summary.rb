# Resumo da O.S. para mandar ao cliente pelo WhatsApp. Hoje sai como link
# wa.me com o texto pronto (a ótica ainda não tem caixa oficial); quando a
# caixa existir, o mesmo texto vai pela conversa do sistema.
class Otica::WhatsappSummary
  def initialize(order, company_name: nil)
    @order = order
    @company_name = company_name.presence || order.account.name
  end

  def text # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    o = @order
    lines = []
    lines << "Olá, #{first_name}! Aqui é da #{@company_name}."
    lines << "Segue o resumo do seu pedido (#{o.label}):"
    o.items.each do |item|
      qty = item.quantity > 1 ? "#{item.quantity}x " : ''
      lines << "• #{qty}#{item.description} — #{money(item.total)}"
    end
    lines << "Desconto: #{money(o.discount)}" if o.discount.to_f.positive?
    lines << "Total: #{money(o.net)}"
    lines << "Pagamento: #{payments_text}" if o.payments.any?
    lines << "Receita: #{o.prescription.summary}" if o.prescription&.summary.present?
    lines << "Previsão de entrega: #{o.due_on.strftime('%d/%m/%Y')}" if o.due_on.present? && !o.delivered?
    lines << "Retirado em #{o.delivered_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y')}." if o.delivered? && o.delivered_at
    lines << 'Qualquer dúvida é só responder por aqui. Obrigado pela confiança!'
    lines.join("\n")
  end

  def link
    digits = @order.contact.phone_number.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    "https://wa.me/#{digits}?text=#{ERB::Util.url_encode(text)}"
  end

  private

  def first_name
    @order.contact.name.to_s.split.first.presence || 'tudo bem'
  end

  def payments_text
    @order.payments.map do |p|
      label = Otica::Payment::METHODS[p.method]
      p.installments > 1 ? "#{label} em #{p.installments}x (#{money(p.amount)})" : "#{label} (#{money(p.amount)})"
    end.join(' + ')
  end

  def money(value)
    whole, cents = format('%.2f', value.to_f).split('.')
    "R$ #{whole.gsub(/(\d)(?=(\d{3})+$)/, '\\1.')},#{cents}"
  end
end
