class CrmListener < BaseListener
  # Toda nova conversa garante um card no funil de entrada do CRM.
  # O card nasce na primeira coluna (menor position) do primeiro pipeline;
  # se o contato já tem card nesse pipeline, nada acontece.
  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    contact = conversation.contact
    return if contact.blank?

    pipeline = account.crm_pipelines.order(:position).first
    return if pipeline.blank?

    entry_stage = pipeline.stages.order(:position).first
    return if entry_stage.blank?

    Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: pipeline.id) do |card|
      card.stage_id = entry_stage.id
      card.origin = conversation.inbox&.name
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # corrida entre eventos simultâneos do mesmo contato — card já existe
    nil
  end
end
