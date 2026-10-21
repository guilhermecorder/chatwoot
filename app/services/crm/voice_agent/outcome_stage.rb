# 📇 Agente de Ligação — o card anda pelo RESULTADO da ligação (item 333,
# 08/10: "podemos ter algo neste agente que mova o card de coluna do CRM?").
# Integrações → Agente de Ligação → "Depois da ligação": para cada resultado
# (sem interesse, prefere WhatsApp, deixou recado, não atendeu…) o admin
# escolhe uma coluna. Quem decide é a regra, não a IA — ela só informa o
# resultado. Marcou/remarcou seguem "Ao marcar" (Crm::BookingSideEffects) e
# confirmou segue a coluna de Consulta Confirmada (Crm::ConfirmationReflector).
#
# Travas: paciente de parceiro nunca; o card só anda PARA A FRENTE (quem já
# está em Consulta Realizada, Cirurgia… fica onde está); e quem tem consulta
# futura marcada não sai do lugar (o resultado da ligação era sobre outra
# coisa) — exceto "cancelou". Dispara as automações da coluna nova, como se a
# equipe tivesse arrastado. Nunca levanta exceção para o pós-chamada.
module Crm::VoiceAgent::OutcomeStage
  module_function

  # devolve o nome da coluna para onde o card foi (ou nil)
  def apply!(call, settings)
    stage = target_stage(call, settings)
    return nil if stage.nil?

    contact = call.contact
    return nil if Crm::PartnerGuard.partner_contact?(contact)
    return nil if call.outcome.to_s != 'cancelou' && future_appointment?(call.account, contact)

    move!(contact, stage)
  rescue StandardError => e
    Rails.logger.warn("[CEVICO voice] card pelo resultado (ligação #{call&.id}): #{e.class}: #{e.message}")
    nil
  end

  def target_stage(call, settings)
    stage_id = settings.outcome_stages[call.outcome.to_s]
    return nil if stage_id.blank? || call.contact.blank?

    stage = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: call.account_id }).find_by(id: stage_id)
    return nil if stage.nil? || stage.pipeline_id == Crm::PartnerGuard.partner_pipeline_id(call.account)

    stage
  end

  def future_appointment?(account, contact)
    Crm::AppointmentRecorder.future_appointment(account, contact.phone_number, nil, contact).present?
  end

  def move!(contact, stage) # rubocop:disable Metrics/AbcSize
    card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
    if card.nil?
      card = Crm::Contact.create!(contact_id: contact.id, pipeline_id: stage.pipeline_id, stage_id: stage.id)
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: stage, event_type: 'card_entered').call
      return stage.name
    end
    return nil if card.stage_id == stage.id
    return nil if card.stage && card.stage.position.to_i > stage.position.to_i # nunca para trás

    previous = card.stage
    card.update!(stage_id: stage.id)
    CrmAutomationTriggerService.new(crm_contact: card, new_stage: stage, previous_stage: previous, event_type: 'card_entered').call
    CrmAutomationTriggerService.new(crm_contact: card, new_stage: previous, previous_stage: previous, event_type: 'card_left').call if previous
    stage.name
  end
end
