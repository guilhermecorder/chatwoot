# 📊 Cron DIÁRIO do Gestor Autônomo (item 128): dias úteis de manhã (11:10
# UTC = 08:10 SP), lê o funil de cada conta com o agente ligado e age
# (achados + tarefas + briefing). Idempotente por dia (last_run_date).
# Modo pontual (botão "Rodar agora"): perform(account_id).
class Crm::AutoManagerJob < ApplicationJob
  queue_as :low

  def perform(account_id = nil)
    return Crm::AutoManagerService.new(account: Account.find(account_id)).call(force: true) if account_id

    CrmSetting.find_each do |settings|
      cfg = ((settings.ai_config || {})['agents'] || {})['manager'] || {}
      next unless cfg['enabled'] == true

      result = Crm::AutoManagerService.new(account: settings.account).call
      Rails.logger.info "[Gestor] conta=#{settings.account_id} #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "[Gestor] conta=#{settings.account_id} falhou: #{e.message}"
    end
  end
end
