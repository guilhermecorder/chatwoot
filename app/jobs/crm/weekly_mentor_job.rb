# Roda o Mentor do Time para as contas com o agente LIGADO (opt-in).
# O cron dispara toda segunda de manhã e analisa a semana que acabou
# (segunda a domingo). Também atende o botão "Gerar feedback agora"
# (admin), que analisa os últimos 7 dias.
class Crm::WeeklyMentorJob < ApplicationJob
  queue_as :low

  # Sem argumentos = rodada do cron (todas as contas, semana fechada).
  # Com account_id = pedido na tela (últimos 7 dias, roda uma vez).
  def perform(account_id = nil)
    if account_id
      account = Account.find(account_id)
      result = Crm::WeeklyMentorService.new(account, rolling: true).call
      Rails.logger.info "[Crm::WeeklyMentor] pontual account=#{account_id} #{result.inspect}"
      return
    end

    CrmSetting.find_each do |settings|
      mentor = ((settings.ai_config || {})['agents'] || {})['mentor'] || {}
      # opt-in explícito: só roda com o interruptor LIGADO (enabled == true)
      next unless mentor['enabled'] == true

      result = Crm::WeeklyMentorService.new(settings.account).call
      Rails.logger.info "[Crm::WeeklyMentor] account=#{settings.account_id} #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "[Crm::WeeklyMentor] account=#{settings.account_id} falhou: #{e.message}"
    end
  end
end
