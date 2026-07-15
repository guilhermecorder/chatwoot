# Consultor Comercial — insights: analisa as conversas que geraram
# fechamento de cirurgia e grava o relatório para a gestão em
# ai_config.agents.sales.insights (aparece no card do agente).
class Crm::SalesInsightsJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find(account_id)
    result = Crm::SalesCoachService.new(account: account).insights

    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    cfg = settings.ai_config || {}
    cfg['agents'] ||= {}
    cfg['agents']['sales'] ||= {}
    cfg['agents']['sales']['insights'] =
      if result[:error]
        { 'error' => result[:error], 'generated_at' => Time.current.iso8601 }
      else
        { 'text' => result[:text], 'conversations' => result[:conversations],
          'generated_at' => result[:generated_at] }
      end
    settings.update!(ai_config: cfg)
  end
end
