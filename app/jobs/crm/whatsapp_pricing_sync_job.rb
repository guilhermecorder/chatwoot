# 💸 item 303: toda manhã puxa da Meta a fatura do WhatsApp dos últimos 35
# dias (a Meta fecha os números com atraso de 1–2 dias; repetir sobrescreve).
# Com account_id + days roda só para aquela conta (botão "Atualizar da Meta").
class Crm::WhatsappPricingSyncJob < ApplicationJob
  queue_as :low
  LOCK_TTL = 15.minutes

  def perform(account_id = nil, days = 35)
    return run_for(Account.find(account_id), days) if account_id

    Account.joins(:inboxes).where(inboxes: { channel_type: 'Channel::Whatsapp' }).distinct.find_each do |account|
      run_for(account, days)
    end
  end

  private

  def run_for(account, days)
    lock_key = "CRM_WA_PRICING_LOCK::#{account.id}"
    return unless Redis::LockManager.new.lock(lock_key, LOCK_TTL.to_i)

    Crm::WhatsappPricingSyncService.new(account: account, days: days).call
  rescue StandardError => e
    Rails.logger.error "[CEVICO gasto whatsapp] conta=#{account.id} falhou: #{e.message}"
  ensure
    Redis::LockManager.new.unlock(lock_key)
  end
end
