# 📣 item 381: de hora em hora, manda a fatia da hora do plano de reativação
# (Crm::ReactivationPlan.run!). Trava por plano: uma rodada longa nunca é
# atropelada pela seguinte.
class Crm::ReactivationPlanJob < ApplicationJob
  queue_as :scheduled_jobs

  LOCK_TTL = 50.minutes

  def perform(campaign_id = nil, force: false)
    scope = Crm::Campaign.processing.where("jsonb_exists(audience, 'reactivation_plan') AND audience ->> 'parent_id' IS NULL")
    scope = scope.where(id: campaign_id) if campaign_id
    scope.find_each { |mother| run_locked(mother, force) }
    Crm::CronHealth.ran!('reactivation_plan') if defined?(Crm::CronHealth)
  end

  private

  def run_locked(mother, force)
    lock_manager = Redis::LockManager.new
    lock_key = "CRM_REACTIVATION_PLAN_LOCK::#{mother.id}"
    return unless lock_manager.lock(lock_key, LOCK_TTL)

    begin
      Crm::ReactivationPlan.run!(mother, force: force)
    rescue StandardError => e
      Rails.logger.error "[Crm::ReactivationPlanJob] plano #{mother.id}: #{e.message}"
      Crm::ReactivationPlan.note!(mother, 'last_error' => e.message.to_s.first(200), 'last_check_at' => Time.current.iso8601)
    ensure
      lock_manager.unlock(lock_key)
    end
  end
end
