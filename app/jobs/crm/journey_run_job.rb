# 🗺️ Motor das mensagens da jornada (item 168): a cada 15 min, para cada
# conta com mensagem ativa, PLANEJA os envios do dia (eventos de hoje) e
# DESPACHA os que já chegaram na hora. Trava por conta no Redis.
# 🛡️ R3: antes de despachar, o Dispatcher#perform também RECONFERE a rodada
# anterior — envio "enviado" que a Meta recusou (Message 'failed') vira
# 'failed' com o erro da Meta, e envio preso em 'sending' há 15 min idem.
class Crm::JourneyRunJob < ApplicationJob
  queue_as :low

  LOCK_TTL = 10.minutes

  def perform(account_id = nil, now: nil)
    accounts = account_id ? Account.where(id: account_id) : accounts_with_messages
    accounts.find_each { |account| run_for(account, now, cron: account_id.nil?) }
    Crm::CronHealth.ran!('jornada') if account_id.nil? # 🚨 #217: sinal de vida da rodada do cron
  end

  private

  def accounts_with_messages
    Account.where(id: Crm::JourneyMessage.active.select(:account_id))
  end

  def run_for(account, now, cron: true)
    lock_key = "CRM_JOURNEY_LOCK::#{account.id}"
    return unless Redis::LockManager.new.lock(lock_key, LOCK_TTL.to_i)

    Crm::Journey::Planner.new(account: account, now: now).perform
    Crm::Journey::Dispatcher.new(account: account, now: now).perform
    # 🔁 item 288: reforço para quem não respondeu (desligado por padrão em cada mensagem)
    Crm::Journey::Followup.new(account: account, now: now).perform
  rescue StandardError => e
    Rails.logger.error("[CEVICO jornada] conta #{account.id}: #{e.message}")
    Crm::CronHealth.failed!('jornada', e, account: account) if cron # 🚨 #217: avisa se repetir (só a rodada do cron)
  ensure
    Redis::LockManager.new.unlock(lock_key)
  end
end
