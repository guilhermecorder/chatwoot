json.email contact.email
json.id contact.id
json.name contact.name
json.phone_number contact.phone_number
json.identifier contact.identifier
json.additional_attributes contact.additional_attributes
json.last_activity_at contact.last_activity_at&.to_i
# CEVICO: em que funil/coluna do CRM o paciente está (pode estar em mais de um)
# + a conversa mais recente, para os atalhos na linha da busca
json.crm_journeys contact.crm_contacts.map { |cc|
  {
    pipeline_id: cc.pipeline_id,
    pipeline_name: cc.pipeline&.name,
    stage_id: cc.stage_id,
    stage_name: cc.stage&.name,
    stage_color: cc.stage&.color
  }
}
json.last_conversation_id contact.conversations.order(last_activity_at: :desc).limit(1).pick(:display_id)
