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
#   f.call    → :enviado (janela de 24 h aberta: texto livre) · :modelo_enviado (janela fechada: vai o ABRIDOR aprovado na
#               Meta e o texto com os números fica guardado — sai quando o cliente responder, Crm::PendingContent)
#               :modelo_pendente (janela fechada e o abridor ainda não foi aprovado) · :sem_dados · :sem_conversa
# 24/11 (Guilherme): "não dá para mandar orçamento por mensagem modelo… elas são para pegar confirmação de sim e não, ou
# para reabrir a conversa". Os modelos com os números (life_orcamento_2_dias_pagamento / 5_dias_prazo) não saem mais.
class Crm::KitQuote::Followup
  STAMP = 'cevico_orcamento_followup'.freeze
  OPENER = 'life_abrir_conversa'.freeze
  OPENER_TEXT = "Oi, {{1}}! Tudo bem?\n\nTenho uma informação sobre a sua proposta de energia solar. Posso te mandar aqui?".freeze
  KINDS = {
    'pagamento' => {
      'rotulo' => 'forma de pagamento',
      'campos' => %w[financiamento financiamento_total cartao_6x preco],
      'texto' => "Oi, {nome}! Sobre o orçamento que eu te mandei, fiz umas contas da forma de pagamento.\n\n" \
                 "No financiamento, os juros pesam: em {financiamento}, o sistema sai por {financiamento_total} no total.\n\n" \
                 'No cartão de crédito, você paga em até 6x sem juros: {cartao_6x} por mês, e o total fica nos {preco} do ' \
                 "orçamento.\n\nQuer garantir nessa condição? Eu já agendo a visita técnica."
    },
    'prazo' => {
      'rotulo' => 'prazo',
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
      'janela_aberta' => open_window?, 'modelo' => OPENER, 'modelo_aprovado' => template_approved?,
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
      t['name'] == OPENER && t['status'].to_s.casecmp('approved').zero?
    end
  end

  def say!
    @conversation.messages.create!(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :outgoing,
                                   content: text, sender: @sender, additional_attributes: { STAMP => @kind_key })
    :enviado
  end

  # janela fechada: o abridor ({{1}} = primeiro nome) e o texto com os números guardado para depois do "pode mandar"
  def send_template!
    name = first_name || 'tudo bem'
    params = { 'name' => OPENER, 'language' => 'pt_BR', 'processed_params' => { 'body' => { '1' => name } } }
    source = Crm::TemplateSource.new(@conversation.account, @conversation.inbox, @sender, params, OPENER_TEXT.gsub('{{1}}', name),
                                     "orcamento-#{@kind_key}")
    return :sem_conversa if Crm::SendTemplateService.new(source: source, contact: @quote.contact).perform.nil?

    Crm::PendingContent.store!(@conversation, text: text, origin: "botão #{@kind['rotulo']}")
    :modelo_enviado
  end
end
