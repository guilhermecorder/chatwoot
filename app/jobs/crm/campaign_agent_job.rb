# 🎯 Agente de Campanhas (item 352): a rodada diária para todas as contas com
# Meta ou Google ligados (cron de madrugada, depois da carga dos anúncios);
# com account_id roda só para aquela conta (botão "Ler agora", force = true).
class Crm::CampaignAgentJob < ApplicationJob
  queue_as :low
  LOCK_TTL = 15.minutes

  def perform(account_id = nil, force: false)
    return run_for(Account.find(account_id), force) if account_id

    CrmSetting.find_each do |settings|
      meta = settings.meta_ads_config || {}
      google = settings.google_ads_config || {}
      next if meta['access_token'].blank? && google['service_account_json'].blank?

      run_for(settings.account, false)
    end
  end

  private

  def run_for(account, force)
    lock_key = "CRM_CAMPAIGN_AGENT_LOCK::#{account.id}"
    return unless Redis::LockManager.new.lock(lock_key, LOCK_TTL.to_i)

    result = Cevico::CampaignAgent::Daily.new(account: account).call(force: force)
    Rails.logger.info "[CEVICO campanhas] conta=#{account.id} #{result.inspect}"
  rescue StandardError => e
    Rails.logger.error "[CEVICO campanhas] conta=#{account.id} falhou: #{e.message}"
  ensure
    Redis::LockManager.new.unlock(lock_key)
  end
end
