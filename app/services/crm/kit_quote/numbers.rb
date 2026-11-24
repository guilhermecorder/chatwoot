# 🔢 NÚMEROS DA PROPOSTA PARA AS MENSAGENS (LIFE, 16/11/2026 · pedido do Guilherme): "puxar esses números do orçamento",
# para o follow-up de fechamento falar com os números da própria pessoa (forma de pagamento, prazo, economia).
#
#   Crm::KitQuote::Numbers.new(quote)[:financiamento]  # => "60x de R$ 520"
#   Crm::KitQuote::Numbers.for(contact)                 # orçamento ativo mais novo do contato (ou nil)
#
# Campos (texto pronto, ou nil quando a proposta não tem o dado):
#   economia      "R$ 3.600 por ano"   economia_ano "R$ 3.600"   economia_mes "R$ 300"   economia_25 "R$ 257.000"
#   preco         "R$ 18.900"          cartao_6x    "R$ 3.150"   (preço ÷ 6, sem juros)
#   financiamento "60x de R$ 520"      (o MAIOR prazo da proposta)  financiamento_total "R$ 31.200" (parcelas × valor)
#   validade      "21/11"              (dia em que a proposta deixa de valer: criação + validade_dias, padrão 7)
#   resumo        endereço público da imagem do resumo
#   economia_10   "R$ 66.500"          (economia em 10 anos, da proposta)
#   investido_10  "R$ 94.300"          (24/11, Guilherme: "se esse dinheiro fosse investido a 1% ao mês, em 10 anos você já tem
#                                       tanto") — a economia de todo mês aplicada a 1% ao mês por 120 meses
class Crm::KitQuote::Numbers
  KEYS = %w[economia economia_ano economia_mes economia_10 economia_25 investido_10 preco cartao_6x financiamento financiamento_total
            validade resumo].freeze
  INVEST_RATE = 0.01 # ao mês
  TIME_ZONE = 'America/Sao_Paulo'.freeze

  def self.for(contact)
    quote = contact && Crm::Quote.ativos.where(contact: contact).recent.first
    quote && new(quote)
  end

  def self.brl(value)
    amount = value.to_f.round
    amount.positive? ? "R$ #{amount.to_s.reverse.scan(/\d{1,3}/).join('.').reverse}" : nil
  end

  def initialize(quote)
    @quote = quote
    @proposal = quote.payload['proposta'] || {}
  end

  def [](key)
    send("field_#{key}") if KEYS.include?(key.to_s)
  end

  def to_h
    KEYS.index_with { |key| self[key] }
  end

  def valid_until
    days = (@proposal.dig('proposta', 'validade_dias') || @proposal['validade_dias']).to_i
    (@quote.created_at.in_time_zone(TIME_ZONE) + (days.positive? ? days : 7).days).to_date
  end

  private

  def brl(value) = self.class.brl(value)
  def economy(key) = @proposal.dig('economia', key)
  def price = @proposal.dig('investimento', 'preco_total').to_f

  def longest_financing
    Array(@proposal.dig('investimento', 'financiamento'))
      .select { |o| o['parcelas'].to_i.positive? && o['valor'].to_f.positive? }
      .max_by { |o| o['parcelas'].to_i }
  end

  def field_economia
    yearly = brl(economy('anual'))
    yearly && "#{yearly} por ano"
  end

  def field_economia_ano = brl(economy('anual'))
  def field_economia_mes = brl(economy('mensal'))
  def field_economia_25 = brl(economy('em_25_anos'))
  def field_economia_10 = brl(economy('em_10_anos'))

  # valor futuro de uma aplicação mensal: P × ((1 + i)^n − 1) / i
  def field_investido_10
    monthly = economy('mensal').to_f
    monthly.positive? ? brl(monthly * (((1 + INVEST_RATE)**120) - 1) / INVEST_RATE) : nil
  end

  def field_preco = brl(price)
  def field_cartao_6x = price.positive? ? brl(price / 6) : nil

  def field_financiamento
    option = longest_financing
    option && "#{option['parcelas'].to_i}x de #{brl(option['valor'])}"
  end

  def field_financiamento_total
    option = longest_financing
    option && brl(option['parcelas'].to_i * option['valor'].to_f)
  end

  def field_validade = valid_until.strftime('%d/%m')

  def field_resumo
    image = @quote.files.find { |f| f.content_type.to_s.start_with?('image/') }
    host = ENV.fetch('FRONTEND_URL', nil)
    image && host ? Rails.application.routes.url_helpers.rails_blob_url(image, host: host) : nil
  end
end
