# 💬 MENSAGEM DE FECHAMENTO COM OS NÚMEROS DA PROPOSTA (LIFE, 16/11/2026 · pedido do Guilherme): "no ambiente dessa
# mensagem, um botão para gerar automático, puxar esses números do orçamento? E os que têm validade."
#
# Dois botões na caixa do orçamento (Gerador e conversa):
#   pagamento → financiamento (maior prazo e o total pago) × cartão em 6x sem juros, com o preço da proposta
#   prazo     → "vale até <dia>" + quanto a pessoa deixa de economizar por mês
# Os números saem de Crm::KitQuote::Numbers (os mesmos do follow-up automático). Falta número → não sai texto pela metade.
#
#   f = Crm::KitQuote::Followup.new(quote, 'pagamento', sender: user)
#   f.preview → { 'texto', 'falta' => [...], 'janela_aberta', 'modelo', 'modelo_aprovado' }
#   f.call    → :enviado (janela de 24 h aberta: texto livre) · :modelo_enviado (janela fechada: modelo aprovado na Meta)
#               :modelo_pendente (janela fechada e o modelo ainda não foi aprovado) · :sem_dados · :sem_conversa
class Crm::KitQuote::Followup
  STAMP = 'cevico_orcamento_followup'.freeze
  KINDS = {
    'pagamento' => {
      'rotulo' => 'forma de pagamento',
      'modelo' => 'life_orcamento_2_dias_pagamento',
      'campos' => %w[financiamento financiamento_total cartao_6x preco],
      'texto' => "Oi, {nome}! Sobre o orçamento que eu te mandei, fiz umas contas da forma de pagamento.\n\n" \
                 "No financiamento, os juros pesam: em {financiamento}, o sistema sai por {financiamento_total} no total.\n\n" \
                 'No cartão de crédito, você paga em até 6x sem juros: {cartao_6x} por mês, e o total fica nos {preco} do ' \
                 "orçamento.\n\nQuer garantir nessa condição? Eu já agendo a visita técnica."
    },
    'prazo' => {
      'rotulo' => 'prazo',
      'modelo' => 'life_orcamento_5_dias_prazo',
      'campos' => %w[validade economia_mes],
      'texto' => "Oi, {nome}! O seu orçamento vale até {validade}.\n\nCada mês sem as placas são {economia_mes} que vão para a " \
                 'CPFL em vez de ficar com você. E os equipamentos acompanham o dólar, então não consigo garantir esse preço na ' \
                 "semana que vem.\n\nQuer garantir agora? Responda \"quero\" que eu agendo a visita técnica."
    }
  }.freeze
  FIELD_NAMES = {
    'financiamento' => 'o financiamento', 'financiamento_total' => 'o financiamento', 'cartao_6x' => 'o preço',
    'preco' => 'o preço', 'validade' => 'a validade', 'economia_mes' => 'a economia por mês'
  }.freeze

  def self.kind?(kind)
    KINDS.key?(kind.to_s)
  end

  def initialize(quote, kind, sender: nil)
    @quote = quote
    @kind = KINDS.fetch(kind.to_s)
    @kind_key = kind.to_s
    @sender = sender
    @numbers = Crm::KitQuote::Numbers.new(quote)
    @conversation = Crm::KitQuote::Delivery.new(quote).conversation
  end

  def preview
    {
      'tipo' => @kind_key, 'rotulo' => @kind['rotulo'], 'texto' => missing.empty? ? text : nil,
      'falta' => missing.map { |key| FIELD_NAMES[key] }.uniq,
      'janela_aberta' => open_window?, 'modelo' => @kind['modelo'], 'modelo_aprovado' => template_approved?,
      'tem_conversa' => @conversation.present?
    }
  end

  def call
    return :sem_conversa if @conversation.nil?
    return :sem_dados if missing.any?
    return say! if open_window?
    return :modelo_pendente unless template_approved?

    send_template!
  end

  private

  def first_name
    @quote.contact&.name.to_s.gsub(/[^\p{L}\p{M}\s'-]/, ' ').split.first.presence
  end

  def values
    @values ||= @kind['campos'].index_with { |key| @numbers[key] }
  end

  def missing
    values.select { |_, value| value.blank? }.keys
  end

  def text
    out = @kind['texto'].gsub('{nome}', first_name || 'tudo bem')
    values.each { |key, value| out = out.gsub("{#{key}}", value.to_s) }
    out
  end

  def open_window?
    @conversation.present? && @conversation.can_reply?
  end

  def template_approved?
    Array(@conversation&.inbox&.channel.try(:message_templates)).any? do |t|
      t['name'] == @kind['modelo'] && t['status'].to_s.casecmp('approved').zero?
    end
  end

  def say!
    @conversation.messages.create!(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :outgoing,
                                   content: text, sender: @sender, additional_attributes: { STAMP => @kind_key })
    :enviado
  end

  # {{1}} = primeiro nome; {{2}}… = os campos na ordem do modelo
  def send_template!
    body = { '1' => first_name || 'tudo bem' }
    @kind['campos'].each_with_index { |key, i| body[(i + 2).to_s] = values[key] }
    params = { 'name' => @kind['modelo'], 'language' => 'pt_BR', 'processed_params' => { 'body' => body } }
    source = Crm::TemplateSource.new(@conversation.account, @conversation.inbox, @sender, params, text, "orcamento-#{@kind_key}")
    return :sem_conversa if Crm::SendTemplateService.new(source: source, contact: @quote.contact).perform.nil?

    :modelo_enviado
  end
end
