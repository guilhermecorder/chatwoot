# Ciclo MENSAL do Mentor do Time: todo dia 1 de manhã, analisa o mês que
# fechou (visão de evolução, não a foto da semana). Mesmo opt-in do
# semanal: só roda com o agente mentor LIGADO.
class Crm::MonthlyMentorJob < ApplicationJob
  queue_as :low

  def perform
    CrmSetting.find_each do |settings|
      mentor = ((settings.ai_config || {})['agents'] || {})['mentor'] || {}
      next unless mentor['enabled'] == true

      result = Crm::WeeklyMentorService.new(settings.account, cadence: 'monthly').call
      Rails.logger.info "[Crm::MonthlyMentor] account=#{settings.account_id} #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "[Crm::MonthlyMentor] account=#{settings.account_id} falhou: #{e.message}"
    end
  end
end
