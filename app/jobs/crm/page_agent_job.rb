# 📄 Agente de Páginas (item 353): a rodada diária para todas as contas com
# página publicada (cron de manhã, depois da foto do Search Console); com
# account_id roda só para aquela conta (botão "Ler agora", force = true).
class Crm::PageAgentJob < ApplicationJob
  queue_as :low
  LOCK_TTL = 15.minutes

  def perform(account_id = nil, force: false)
    return run_for(Account.find(account_id), force) if account_id

    Account.where(id: CevicoPage.where(status: 'published').distinct.select(:account_id)).find_each { |account| run_for(account, false) }
  end

  private

  def run_for(account, force)
    lock_key = "CRM_PAGE_AGENT_LOCK::#{account.id}"
    return unless Redis::LockManager.new.lock(lock_key, LOCK_TTL.to_i)

    result = Cevico::PageAgent::Daily.new(account: account).call(force: force)
    Rails.logger.info "[CEVICO páginas] conta=#{account.id} #{result.inspect}"
  rescue StandardError => e
    Rails.logger.error "[CEVICO páginas] conta=#{account.id} falhou: #{e.message}"
  ensure
    Redis::LockManager.new.unlock(lock_key)
  end
end
