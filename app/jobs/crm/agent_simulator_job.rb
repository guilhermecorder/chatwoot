# ⏱️ 🧪 Testar agente em SEGUNDO PLANO (item 414, 24/11/2026): a resposta do
# agente a uma fala da conversa de teste roda aqui, fora da chamada da tela
# (que o servidor corta em 15 s). O resultado fica na conversa (nota de sombra)
# e o estado no Redis (Crm::AgentSimulator.status); a tela pergunta até ficar pronto.
#
# Fila 'ai_fundo' (IA de bastidor): um teste nunca disputa vaga com paciente de
# verdade, que roda na fila 'ai'. Sem nova tentativa: o erro tem que aparecer
# na tela do teste, e repetir gastaria a IA de novo.
class Crm::AgentSimulatorJob < ApplicationJob
  queue_as :ai_fundo
  sidekiq_options retry: 0

  def perform(conversation_id, message_id, agent_key, model = nil, consultant = nil)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil? || !Crm::AgentSimulator.simulated?(conversation)

    message = conversation.messages.find_by(id: message_id)
    return Crm::AgentSimulator.finish!(conversation, message_id, error: 'A fala do teste não foi encontrada.') if message.nil?

    simulator = Crm::AgentSimulator.new(account: conversation.account, agent_key: agent_key)
    outcome = simulator.reply!(conversation, message, model: model, consultant: consultant)
    Crm::AgentSimulator.finish!(conversation, message_id, error: outcome[:error])
  rescue StandardError => e
    Rails.logger.error "[Crm::AgentSimulatorJob] #{e.class}: #{e.message}"
    Crm::AgentSimulator.finish!(conversation, message_id, error: e.message.to_s.truncate(200)) if conversation
  end
end
