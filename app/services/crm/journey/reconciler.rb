# 🛡️ auditoria R3 (#45/#46): a Meta pode recusar o modelo DEPOIS que a
# jornada gravou 'sent' (o webhook marca a Message como 'failed'). A cada
# rodada do cron (Dispatcher#perform), envio "enviado" cuja mensagem falhou
# vira 'failed' com o erro da Meta — e a equipe reenvia pela tela. Envio
# preso em 'sending' há mais de 15 min (o processo morreu no meio) também
# vira 'failed', pedindo para conferir a conversa antes de reenviar.
class Crm::Journey::Reconciler
  # envio preso em 'sending' por mais que isso = o processo morreu no meio
  STUCK_AFTER = 15.minutes
  # até quando olhamos para trás para ver se a Meta recusou um envio "enviado"
  WINDOW = 48.hours
  STUCK_ERROR = 'O envio travou no meio (o sistema reiniciou?). Confira a conversa antes de reenviar'.freeze

  attr_reader :account, :now

  def initialize(account:, now:)
    @account = account
    @now = now
  end

  # devolve quantos envios mudaram de status
  def perform
    fail_stuck_sending! + fail_refused_by_meta!
  end

  private

  def fail_stuck_sending!
    Crm::JourneySend.where(account: account, status: 'sending').where(updated_at: ...(now - STUCK_AFTER))
                    .update_all(status: 'failed', error: STUCK_ERROR, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def fail_refused_by_meta!
    sent = Crm::JourneySend.where(account: account, status: 'sent', sent_at: (now - WINDOW)..).pluck(:id, :variables)
    by_message = sent.to_h { |id, vars| [(vars || {})[Crm::JourneySend::MESSAGE_ID_KEY].to_i, id] }.except(0)
    return 0 if by_message.empty?

    # a porta única do modelo é quem sabe ler a recusa da Meta
    refused = Crm::SendTemplateService.refused(by_message.keys)
    refused.each do |msg_id, detail|
      Crm::JourneySend.where(id: by_message[msg_id], status: 'sent')
                      .update_all(status: 'failed', error: "A Meta recusou a mensagem: #{detail}".truncate(300), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
    refused.size
  end
end
