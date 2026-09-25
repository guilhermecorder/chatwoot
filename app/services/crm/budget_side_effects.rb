# 💰 item 236 (25/09): o card anda SOZINHO para "Envio de Orçamento" quando a
# clínica (robô ou equipe) manda um VALOR na conversa. Pedido do Guilherme: a
# automação por palavras ("Consulta confirmada", "Deu certo"…) "não é 100%
# precisa" e muito lead pulava de Novos Contatos direto para Agendamento sem
# passar pelo orçamento — a taxa oficial (item 233) precisa da passagem certa.
#
# Regra: mensagem de SAÍDA (não privada) com "R$ 1.234" / "1.234 reais" →
# se o card do 1º funil está ANTES da coluna de orçamento, move para ela (só
# pra frente, nunca volta) e dispara as automações da coluna como se a equipe
# tivesse arrastado. Coluna: agenda_config.booking.budget_stage_id
# (Agendamentos → Ajustes) ou, sem configurar, a coluna do 1º funil com
# "orçamento" no nome. Paciente de parceiro nunca chega aqui (cerca, item 231).
module Crm::BudgetSideEffects
  module_function

  PRICE = /R\$\s?\d|\b\d{1,3}(\.\d{3})+(,\d{2})?\s*reais\b|\b\d+\s*reais\b/i

  def price_message?(message)
    return false if message.blank? || message.message_type != 'outgoing' || message.private?

    PRICE.match?(message.content.to_s)
  end

  def stage(account) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cfg = (CrmSetting.find_by(account: account)&.agenda_config || {})['booking'] || {}
    id = cfg['budget_stage_id'].presence&.to_i
    found = id && Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).find_by(id: id)
    return found if found

    pipeline = account.crm_pipelines.order(:position).first
    pipeline&.stages&.order(:position)&.detect { |s| s.name.match?(/or[çc]amento/i) }
  end

  # devolve o nome da coluna quando moveu; nil quando não havia o que fazer
  def apply(account:, contact:, message:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    return nil if contact.blank? || !price_message?(message)

    target = stage(account)
    return nil if target.blank?

    card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: target.pipeline_id)
    return nil if card.blank? # sem card no funil = não é lead da CEVICO (ex.: parceiro)

    current = card.stage
    return nil if current.blank? || current.position.to_i >= target.position.to_i # já passou (ou está) do orçamento

    card.update!(stage_id: target.id)
    CrmAutomationTriggerService.new(crm_contact: card, new_stage: target, previous_stage: current, event_type: 'card_entered').call
    CrmAutomationTriggerService.new(crm_contact: card, new_stage: current, previous_stage: current, event_type: 'card_left').call
    Rails.logger.info "[Crm::BudgetSideEffects] contato #{contact.id}: #{current.name} → #{target.name} (valor na mensagem #{message.id})"
    target.name
  rescue StandardError => e
    Rails.logger.warn "[Crm::BudgetSideEffects] #{e.class}: #{e.message}"
    nil
  end
end
