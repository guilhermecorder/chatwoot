# Webhook pós-chamada da ElevenLabs precisa de resposta rápida: o
# controller só valida a assinatura e enfileira aqui; o serviço fecha a
# ligação (card, transcrição, campanha, uso de IA) com calma na fila low.
class Crm::VoiceAgent::PostCallJob < ApplicationJob
  queue_as :low

  def perform(account_id, payload)
    account = Account.find_by(id: account_id)
    return if account.blank?

    Crm::VoiceAgent::PostCallService.new(account: account, payload: payload).perform
  rescue StandardError => e
    Rails.logger.error("[CEVICO voice] pós-chamada conta #{account_id}: #{e.class}: #{e.message}")
    raise
  end
end
