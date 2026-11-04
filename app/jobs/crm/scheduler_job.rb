# Roda a cada 5 minutos (config/schedule.yml):
# 1. dispara campanhas agendadas que venceram
# 2. processa as réguas de mensagens (automações por etiqueta + tempo)
class Crm::SchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    trigger_due_campaigns
    run_message_automations
  end

  private

  # 🔁 item 379: a campanha RECORRENTE (mãe) venceu → abre a rodada (filha) e
  # marca a próxima data; a campanha comum sai como sempre. Uma mãe com
  # problema não segura as outras.
  def trigger_due_campaigns
    Crm::Campaign.due.find_each do |campaign|
      if campaign.recurring?
        Crm::RecurringCampaign.spawn!(campaign)
      else
        campaign.update!(status: :processing)
        Crm::CampaignRunJob.perform_later(campaign.id)
      end
    rescue StandardError => e
      Rails.logger.error "[Crm::SchedulerJob] campanha #{campaign.id}: #{e.message}"
    end
  end

  def run_message_automations
    Crm::MessageAutomation.active.find_each do |automation|
      Crm::MessageAutomationRunJob.perform_later(automation.id)
    end
  end
end
