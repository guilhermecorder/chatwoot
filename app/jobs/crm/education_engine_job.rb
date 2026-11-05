# 🎓 Cron DIÁRIO do Motor de Educação (item 389): 11:10 UTC (08:10 SP), depois
# do Auditor. Lê as conversas de ONTEM de cada conta com o motor ligado e deixa
# as sugestões esperando a aprovação do admin. Idempotente por dia.
# Pontual (botão "Ler ontem agora"): perform(account_id, 'AAAA-MM-DD') — força.
class Crm::EducationEngineJob < ApplicationJob
  queue_as :low

  def perform(account_id = nil, day = nil)
    if account_id
      date = day.present? ? Date.iso8601(day.to_s) : Crm::EducationEngine::TZ.yesterday
      return Crm::EducationEngine.new(account: Account.find(account_id)).call(day: date, force: true)
    end

    CrmSetting.find_each do |settings|
      next unless ((settings.ai_config || {})['motor'] || {})['enabled'] == true

      result = Crm::EducationEngine.new(account: settings.account).call
      Rails.logger.info "[Motor] conta=#{settings.account_id} #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "[Motor] conta=#{settings.account_id} falhou: #{e.message}"
    end
  end
end
