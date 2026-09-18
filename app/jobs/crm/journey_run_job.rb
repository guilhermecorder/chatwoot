# 🗺️ Motor das mensagens da jornada (item 168): a cada 15 min, para cada
# conta com mensagem ativa, PLANEJA os envios do dia (eventos de hoje) e
# DESPACHA os que já chegaram na hora. Trava por conta no Redis.
class Crm::JourneyRunJob < ApplicationJob
  queue_as :low

  LOCK_TTL = 10.minutes

  def perform(account_id = nil, now: nil)
    accounts = account_id ? Account.where(id: account_id) : accounts_with_messages
    accounts.find_each { |account| run_for(account, now) }
  end

  private

  def accounts_with_messages
    Account.where(id: Crm::JourneyMessage.active.select(:account_id))
  end

  def run_for(account, now)
    lock_key = "CRM_JOURNEY_LOCK::#{account.id}"
    return unless Redis::LockManager.new.lock(lock_key, LOCK_TTL.to_i)

    Crm::Journey::Planner.new(account: account, now: now).perform
    Crm::Journey::Dispatcher.new(account: account, now: now).perform
  rescue StandardError => e
    Rails.logger.error("[CEVICO jornada] conta #{account.id}: #{e.message}")
  ensure
    Redis::LockManager.new.unlock(lock_key)
  end
end
