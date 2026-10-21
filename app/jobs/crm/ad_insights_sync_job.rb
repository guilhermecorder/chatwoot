# Central de Criativos (item 172): puxa da Meta os anúncios + métricas diárias.
# Cron de madrugada para todas as contas configuradas; com account_id roda
# só para aquela conta (botão "Atualizar dados"). Trava por conta no Redis.
class Crm::AdInsightsSyncJob < ApplicationJob
  queue_as :low
  LOCK_TTL = 20.minutes

  def perform(account_id = nil, days = nil)
    return run_for(Account.find(account_id), days) if account_id

    CrmSetting.find_each do |settings|
      cfg = settings.meta_ads_config || {}
      next if cfg['access_token'].blank? || cfg['ad_account_id'].blank?

      run_for(settings.account, nil)
    end
  end

  private

  def run_for(account, days)
    lock_key = "CRM_AD_INSIGHTS_LOCK::#{account.id}"
    return unless Redis::LockManager.new.lock(lock_key, LOCK_TTL.to_i)

    result = Crm::AdInsightsSyncService.new(account: account, days: days).call
    Rails.logger.info "[CEVICO criativos] conta=#{account.id} #{result.inspect}"
  rescue StandardError => e
    Rails.logger.error "[CEVICO criativos] conta=#{account.id} falhou: #{e.message}"
  ensure
    Redis::LockManager.new.unlock(lock_key)
  end
end
