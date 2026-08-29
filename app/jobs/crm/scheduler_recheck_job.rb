# RELEITURA do Secretário da Agenda (rodada 148 — "agendamento 100%"):
# disparada pelo CrmListener quando chega mensagem de um paciente que
# (a) tem tarefa de revisão aberta ("⚠️ Confirmar consulta") — a resposta
#     dele provavelmente traz o dia/hora que faltava; ou
# (b) falou em remarcar/cancelar E tem consulta futura na Agenda.
# A espera de 20s junta mensagens picadas antes de ler. A leitura em si é o
# mesmo Crm::AppointmentApplier das automações de coluna.
class Crm::SchedulerRecheckJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    contact = conversation&.contact
    return if conversation.blank? || contact.blank?

    Crm::AppointmentApplier.call(
      account: conversation.account,
      contact: contact,
      conversation: conversation, # a conversa onde o paciente escreveu
      default_unit: default_unit_for(conversation.account_id)
    )
  end

  private

  # unidade padrão: a mesma configurada em qualquer automação do Secretário
  def default_unit_for(account_id)
    Crm::Automation.joins(stage: :pipeline)
                   .where(crm_pipelines: { account_id: account_id })
                   .where(action_type: 'schedule_appointment')
                   .where("action_config ->> 'default_unit' IS NOT NULL")
                   .pick(Arel.sql("action_config ->> 'default_unit'"))
                   .presence
  end
end
