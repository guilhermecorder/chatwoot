# 🧭 ETIQUETAS DA JORNADA (LIFE, 13/11/2026 · "deixe a automação feita para que as pessoas estejam sempre na coluna certa").
# Cada passo do cliente põe uma etiqueta no contato; a automação "Etiqueta adicionada" da coluna onde o cartão está
# leva o cartão para a coluna certa (só para frente: a automação só existe nas colunas de antes). Etiquetas:
#   sondagem          → Solicitação da Conta   (ficha: imóvel, telhado, cidade ou conta anotados)
#   conta-recebida    → Orçamento a fazer      (aqui: orçamento automático pedido ou tarefa "Orçamento: conta recebida")
#   orcamento-gerado  → Orçamento pronto       (Gerador / Crm::KitQuote::CardUpdate)
#   orcamento-enviado → Orçamento Enviado      (Crm::QuoteSent)
#   quer-fechar       → Vistoria Técnica Agendada (ficha: forma de pagamento anotada pelo Atendente do Orçamento)
# As automações e os campos da ficha são gravados pelo console (LIFE/agente/aplicar_v18_agentes_e_colunas.rb).
module Crm::JourneyLabel
  BILL_RECEIVED = 'conta-recebida'.freeze
  QUOTE_TASK = /\AOrçamento: (conta recebida|aumento de consumo)/i

  module_function

  def quote_task?(motivo)
    motivo.to_s.match?(QUOTE_TASK)
  end

  def bill_received!(contact)
    add!(contact, BILL_RECEIVED)
  end

  def add!(contact, label)
    return if contact.nil? || contact.label_list.include?(label)

    contact.account.labels.find_or_create_by!(title: label)
    contact.add_labels([label])
  rescue StandardError => e
    Rails.logger.warn "[Crm::JourneyLabel] #{label}: #{e.message}"
  end
end
