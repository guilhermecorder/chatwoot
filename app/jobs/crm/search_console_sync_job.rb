# 🔎 Search Console (16/10): toda manhã guarda a foto dos últimos 28 dias do
# Google (impressões, cliques, CTR, posição e termos por página) para a aba
# Otimizar dos Resultados de tráfego. Com account_id roda só para aquela
# conta (botão "Atualizar agora"). Trava por conta no Redis.
class Crm::SearchConsoleSyncJob < ApplicationJob
  queue_as :low
  LOCK_TTL = 10.minutes

  def perform(account_id = nil)
    return run_for(Account.find(account_id)) if account_id

    CrmSetting.find_each do |settings|
      next if (settings.google_ads_config || {})['service_account_json'].blank?

      run_for(settings.account)
    end
  end

  private

  def run_for(account)
    lock_key = "CRM_SEARCH_CONSOLE_LOCK::#{account.id}"
    return unless Redis::LockManager.new.lock(lock_key, LOCK_TTL.to_i) # outra rodada em andamento

    begin
      result = Cevico::SearchConsole.new(account).sync!
      Rails.logger.info "[CEVICO search console] conta=#{account.id} #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "[CEVICO search console] conta=#{account.id} falhou: #{e.message}"
    ensure
      Redis::LockManager.new.unlock(lock_key)
    end
  end
end
