# 👋 08/11 (LIFE): 3 minutos depois da boas-vindas do lead do formulário,
# confere se a Meta recusou a mensagem modelo (status 'failed': número sem
# WhatsApp, modelo pausado…). Recusou → tarefa para a equipe chamar o lead,
# senão ele fica sem resposta nenhuma.
class Crm::MetaLeadWelcomeCheckJob < ApplicationJob
  queue_as :low

  def perform(message_id, leadgen_id)
    refused = Crm::SendTemplateService.refused([message_id])
    return if refused.empty?

    message = Message.find_by(id: message_id)
    conversation = message&.conversation
    return if conversation.blank?

    Crm::HandoffTask.open!(account: conversation.account, contact: conversation.contact, conversation: conversation,
                           agent_key: 'atendente_agendamento',
                           motivo: 'Chamar lead do formulário do Meta (a Meta recusou a mensagem de boas-vindas)',
                           detalhes: "Erro da Meta: #{refused[message_id]} · lead #{leadgen_id}")
  end
end
