# 🎨 Cron SEMANAL do Criativo Perpétuo (item 131): segunda 11:30 UTC
# (08:30 SP) — encontra os vencedores da semana e gera as variações para
# aprovação. Idempotente por semana (week_key).
# Modo pontual (botão "Gerar agora"): perform(account_id).
class Crm::CreativeJob < ApplicationJob
  queue_as :low

  def perform(account_id = nil)
    return Crm::CreativeService.new(account: Account.find(account_id)).call(force: true) if account_id

    CrmSetting.find_each do |settings|
      cfg = ((settings.ai_config || {})['agents'] || {})['creative'] || {}
      next unless cfg['enabled'] == true

      result = Crm::CreativeService.new(account: settings.account).call
      Rails.logger.info "[Criativo] conta=#{settings.account_id} #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "[Criativo] conta=#{settings.account_id} falhou: #{e.message}"
    end
  end
end
