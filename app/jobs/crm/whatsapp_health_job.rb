# 🚦 Saúde do WhatsApp (16/10/2026): de hora em hora, para cada conta com
# WhatsApp — (1) anota a nota da Meta de cada número quando ela MUDA (linha do
# tempo da tela; a Meta só informa a nota de agora) e (2) roda a varredura
# da suspeita de bloqueio. Com account_id roda só aquela conta (botão
# "Conferir agora" da tela).
class Crm::WhatsappHealthJob < ApplicationJob
  queue_as :low
  LOCK_TTL = 20.minutes

  def perform(account_id = nil)
    return run_for(Account.find(account_id)) if account_id

    Account.joins(:inboxes).where(inboxes: { channel_type: 'Channel::Whatsapp' }).distinct.find_each do |account|
      run_for(account) if account.active?
    end
  end

  private

  def run_for(account)
    lock_key = "CRM_WA_HEALTH_LOCK::#{account.id}"
    return unless Redis::LockManager.new.lock(lock_key, LOCK_TTL.to_i)

    Crm::WhatsappHealthLog.record!(account)
    result = Crm::BlockSuspicionScan.new(account).call
    Rails.logger.info "[CEVICO saúde whatsapp] conta=#{account.id} #{result.to_json}"
  rescue StandardError => e
    Rails.logger.error "[CEVICO saúde whatsapp] conta=#{account.id} falhou: #{e.message}"
  ensure
    Redis::LockManager.new.unlock(lock_key)
  end
end
