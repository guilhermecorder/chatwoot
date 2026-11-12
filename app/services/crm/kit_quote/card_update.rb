# 🗂️ ORÇAMENTO GERADO → CARTÃO E FICHA DO CLIENTE (LIFE, 12/11/2026 · pedido do Guilherme): "na hora de gerar,
# atualize o card do lead com as tags, o valor e tudo, de modo que o atendente saiba os valores e os parcelamentos".
#
#   Crm::KitQuote::CardUpdate.call(quote)
#     · etiqueta `orcamento-gerado` no contato;
#     · valor do orçamento no cartão do funil;
#     · linha "Orçamento" na ficha do cliente (o atendente lê a ficha): valor, kit, cartão, financiamento e validade.
# O piso de negociação NÃO vai para a ficha (o atendente não negocia: leva a contraproposta para o Fernando).
class Crm::KitQuote::CardUpdate
  LABEL = 'orcamento-gerado'.freeze
  COLOR = '#F59E0B'.freeze
  FIELD = 'orcamento'.freeze
  TYPES = { 'micro' => 'micro inversor', 'string' => 'inversor string', 'hibrido' => 'inversor híbrido' }.freeze

  def self.call(quote)
    new(quote).call
  end

  def initialize(quote)
    @quote = quote
    @contact = quote.contact
  end

  def call
    return if @contact.nil?

    label!
    Crm::QuoteSent.store_value(@contact, @quote.price)
    write_summary!
  rescue StandardError => e
    Rails.logger.warn "[Gerador de proposta] cartão/ficha do orçamento #{@quote.id}: #{e.message}"
  end

  def summary_text
    [money(@quote.price), kit_text, equipment_text, card_text, financing_text, "vale até #{valid_until}"].compact_blank.join(' · ')
  end

  private

  def invest
    @quote.payload.dig('proposta', 'investimento').to_h
  end

  def kit_text
    option = @quote.payload['opcao'].to_h
    [TYPES[@quote.kind] || @quote.kind, option['placas'].presence && "#{option['placas']} placas",
     option['potencia_kwp'].presence && "#{decimal(option['potencia_kwp'])} kWp"].compact.join(', ')
  end

  # o modelo do equipamento (o cliente pergunta: "os microinversores são de qual modelo?")
  def equipment_text
    option = @quote.payload['opcao'].to_h
    [option['paineis'], option['inversor']].compact_blank.join(' + ').first(220).presence
  end

  def card_text
    invest['cartao'].present? ? "cartão: #{invest['cartao'].to_s.sub(/\s*\(.*\)\z/, '')}" : nil
  end

  def financing_text
    longest = Array(invest['financiamento']).max_by { |f| f['parcelas'].to_i }
    longest ? "financiamento em até #{longest['parcelas']}x de #{money(longest['valor'])} (sujeito a aprovação)" : nil
  end

  def label!
    @contact.account.labels.find_or_create_by!(title: LABEL) do |label|
      label.color = COLOR
      label.description = 'Cliente com orçamento gerado no Gerador de proposta (posta sozinha)'
      label.show_on_sidebar = true
    end
    @contact.add_labels([LABEL]) unless @contact.label_list.include?(LABEL)
  end

  def write_summary!
    return unless Crm::ClientSummary.fields(@contact.account).any? { |f| f['chave'] == FIELD }

    Crm::ClientSummary.write!(@contact, { FIELD => summary_text }, by: 'Gerador de proposta')
  end

  def valid_until
    days = (@quote.payload.dig('proposta', 'proposta', 'validade_dias') || @quote.payload.dig('proposta', 'validade_dias')).to_i
    (@quote.created_at.in_time_zone('America/Sao_Paulo') + (days.positive? ? days : 7).days).strftime('%d/%m')
  end

  def money(value)
    whole, cents = format('%.2f', value.to_f).split('.')
    "R$ #{whole.reverse.scan(/\d{1,3}/).join('.').reverse}#{",#{cents}" unless cents == '00'}"
  end

  def decimal(value)
    format('%.2f', value.to_f).sub('.', ',').sub(/,?0+\z/, '')
  end
end
