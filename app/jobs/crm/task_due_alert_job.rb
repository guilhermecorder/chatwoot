# ⏰ 08/11/2026 (LIFE): chegou o DIA E HORA de uma tarefa com data marcada pelo
# atendente de IA ("daqui a 3, 4 dias eu te chamo") → aviso no Radar do Meu
# Painel do responsável (Crm::AgentAlert, kind 'tarefa_no_prazo'), com o botão de
# atender a conversa. Agendado por Crm::HandoffTask quando a tarefa nasce e pelo
# Task quando mudam a data na tela. Não avisa se a tarefa já foi feita,
# cancelada, ou se mudaram o prazo para depois.
class Crm::TaskDueAlertJob < ApplicationJob
  queue_as :default
  GRACE = 2.minutes

  def perform(task_id, conversation_id = nil)
    task = Task.find_by(id: task_id)
    return unless due_now?(task)

    Crm::AgentAlert.push(account: task.account, kind: Crm::AgentAlert::DUE_KIND, task: task,
                         conversation: conversation_for(task, conversation_id), agent_key: 'atendente_agendamento')
  end

  private

  def due_now?(task)
    return false if task.nil? || task.canceled_at.present? || task.done?

    task.due_at.blank? || task.due_at <= GRACE.from_now
  end

  # data mudada na tela: o aviso nasce sem conversa → a mais recente do contato
  def conversation_for(task, conversation_id)
    found = Conversation.find_by(id: conversation_id, account_id: task.account_id) if conversation_id
    found || task.contact&.conversations&.order(last_activity_at: :desc)&.first
  end
end
