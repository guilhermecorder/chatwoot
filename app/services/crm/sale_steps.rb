# 🧭 ETAPA DA VENDA DE UM CLIENTE (LIFE, 18/11/2026 · pedido do Guilherme): "encontrar formas, por exemplo, do
# Fernando apertar um botão… porque no meu painel ele não está registrando, enquanto na realidade a gente já
# conseguiu avançar".
#
# A régua é a mesma da Jornada da venda do Meu Painel (Crm::QuoteJourney): aqui ela é lida para UMA pessoa, e a
# equipe marca à mão as etapas de depois do orçamento, pelos botões "Etapa da venda" (conversa e Central do cliente).
#
# Marcar = pôr a etiqueta da etapa no contato (a automação "Etiqueta adicionada" da coluna leva o cartão para a
# coluna certa). A forma de pagamento vai para a ficha do cliente (campo forma_pagamento → etiqueta `quer-fechar`).
#   investimento → investimento-possivel     pagamento → ficha forma_pagamento
#   credito      → credito-pre-aprovado      proposta  → proposta-de-fechamento
#   fechado      → contrato-fechado          instalado → instalacao-realizada
class Crm::SaleSteps
  MARKS = {
    'investimento' => 'investimento-possivel',
    'credito' => 'credito-pre-aprovado',
    'proposta' => 'proposta-de-fechamento',
    'fechado' => 'contrato-fechado',
    'instalado' => 'instalacao-realizada'
  }.freeze
  PAYMENT_STEP = 'pagamento'.freeze
  PAYMENT_FIELD = 'forma_pagamento'.freeze
  PAYMENTS = { 'cartao' => 'cartão de crédito', 'financiamento' => 'financiamento', 'a_vista' => 'à vista' }.freeze
  PAYMENT_LABELS = { 'cartao' => 'Cartão', 'financiamento' => 'Financiamento', 'a_vista' => 'À vista' }.freeze
  HINTS = {
    'investimento' => 'Disse que é possível fazer o investimento',
    'pagamento' => 'Escolheu como vai pagar',
    'credito' => 'CPF recebido e crédito pré-aprovado (só no financiamento)',
    'proposta' => 'Proposta de fechamento enviada',
    'fechado' => 'Contrato assinado',
    'instalado' => 'Sistema instalado e gerando'
  }.freeze

  def self.markable?(key)
    MARKS.key?(key) || key == PAYMENT_STEP
  end

  # o que a tela mostra: as etapas, até onde a pessoa chegou e o que foi marcado à mão
  def self.for(contact)
    reached = Crm::QuoteJourney.new(contact.account, contact_ids: [contact.id]).reached_index(contact.id)
    payment = payment_of(contact)
    marked = contact.label_list.to_set(&:downcase)
    steps = Crm::QuoteJourney::STEPS.each_with_index.map do |step, index|
      done = step[:key] == PAYMENT_STEP ? payment.present? : marked.include?(MARKS[step[:key]].to_s)
      step_row(step, index, reached).merge(marked: done)
    end
    { steps: steps, current: Crm::QuoteJourney::STEPS[reached][:key], payment: payment,
      payments: PAYMENT_LABELS.map { |key, label| { key: key, label: label } } }
  end

  def self.payment_of(contact)
    contact.additional_attributes.to_h.dig(Crm::ClientSummary::ATTR_KEY, PAYMENT_FIELD, 'valor').to_s.presence
  end

  def self.step_row(step, index, reached)
    key = step[:key]
    { key: key, label: step[:label], hint: HINTS[key], reached: index <= reached, current: index == reached, markable: markable?(key) }
  end

  # marca a etapa; devolve false quando a etapa não é de marcar à mão (ou a forma de pagamento não veio)
  def self.mark!(contact, key, by:, payment: nil)
    return write_payment!(contact, PAYMENTS[payment.to_s], by) if key == PAYMENT_STEP

    label = MARKS[key]
    return false if label.nil?

    contact.account.labels.find_or_create_by!(title: label)
    contact.add_labels([label]) unless contact.label_list.include?(label)
    true
  end

  # desfaz uma marcação feita à mão
  def self.unmark!(contact, key, by:)
    return write_payment!(contact, '', by, clear: true) if key == PAYMENT_STEP

    label = MARKS[key]
    return false if label.nil?

    contact.update_labels(contact.label_list - [label])
    true
  end

  def self.write_payment!(contact, value, by, clear: false)
    return false if value.nil? || (value.blank? && !clear)
    return false unless Crm::ClientSummary.fields(contact.account).any? { |f| f['chave'] == PAYMENT_FIELD }

    Crm::ClientSummary.write!(contact, { PAYMENT_FIELD => value }, by: by)
    true
  end
  private_class_method :write_payment!, :step_row, :payment_of
end
