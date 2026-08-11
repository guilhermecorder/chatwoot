# 🎓 Cron DIÁRIO do Auditor de Conversas (item 130): 10:40 UTC (07:40 SP),
# audita as conversas de ONTEM de cada conta com o agente ligado — 100% de
# cobertura até o teto diário. Idempotente por dia (days_done).
# Modo pontual (botão "Auditar agora"): perform(account_id) — re-audita ontem.
class Crm::ConversationAuditorJob < ApplicationJob
  queue_as :low

  def perform(account_id = nil)
    if account_id
      return Crm::ConversationAuditorService.new(account: Account.find(account_id))
                                            .call(force: true)
    end

    CrmSetting.find_each do |settings|
      cfg = ((settings.ai_config || {})['agents'] || {})['auditor'] || {}
      next unless cfg['enabled'] == true

      result = Crm::ConversationAuditorService.new(account: settings.account).call
      Rails.logger.info "[Auditor] conta=#{settings.account_id} #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "[Auditor] conta=#{settings.account_id} falhou: #{e.message}"
    end
  end
end
