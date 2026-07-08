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

  def trigger_due_campaigns
    Crm::Campaign.due.find_each do |campaign|
      campaign.update!(status: :processing)
      Crm::CampaignRunJob.perform_later(campaign.id)
    end
  end

  def run_message_automations
    Crm::MessageAutomation.active.find_each do |automation|
      Crm::MessageAutomationRunJob.perform_later(automation.id)
    end
  end
end
