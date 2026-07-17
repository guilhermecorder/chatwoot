# Roda o Respondedor de Comentários (IG/FB) para as contas com o agente
# LIGADO e token da Página configurado. Cron a cada 5 minutos.
class Crm::CommentsAgentJob < ApplicationJob
  queue_as :low

  def perform
    CrmSetting.find_each do |settings|
      agent = ((settings.ai_config || {})['agents'] || {})['comments'] || {}
      next unless agent['enabled'] == true
      next if agent['page_access_token'].blank?

      result = Crm::CommentsAgentService.new(settings.account).call
      Rails.logger.info "[Crm::CommentsAgent] account=#{settings.account_id} #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "[Crm::CommentsAgent] account=#{settings.account_id} falhou: #{e.message}"
    end
  end
end
