# 📣 item 381: de hora em hora, manda a fatia da hora do plano de reativação
# (Crm::ReactivationPlan.run!). Trava por plano: uma rodada longa nunca é
# atropelada pela seguinte.
#
# 📤 24/11: o lote APROVADO na tela também sai por aqui (approved_ids). Antes
# o "Aprovar e enviar" mandava dentro do próprio clique: sem a trava (duas abas
# = duas mensagens por pessoa) e, com mais de ~30 pessoas, o servidor cortava o
# pedido em 15 s no meio do envio (parte recebia, a tela dizia que falhou e o
# registro do lote não fechava).
class Crm::ReactivationPlanJob < ApplicationJob
  queue_as :scheduled_jobs

  LOCK_TTL = 50.minutes
  # lote aprovado que encontra a trava ocupada (o robô da hora está rodando) tenta de novo
  RETRY_WAIT = 15.seconds
  MAX_ATTEMPTS = 20

  def perform(campaign_id = nil, force: false, approved_ids: nil, whole_day: false, attempt: 1)
    scope = Crm::Campaign.processing.where("jsonb_exists(audience, 'reactivation_plan') AND audience ->> 'parent_id' IS NULL")
    scope = scope.where(id: campaign_id) if campaign_id
    scope.find_each { |mother| run_locked(mother, force: force, approved_ids: approved_ids, whole_day: whole_day, attempt: attempt) }
    Crm::CronHealth.ran!('reactivation_plan') if defined?(Crm::CronHealth) && approved_ids.nil?
  end

  private

  def run_locked(mother, force:, approved_ids:, whole_day:, attempt:)
    lock_manager = Redis::LockManager.new
    lock_key = "CRM_REACTIVATION_PLAN_LOCK::#{mother.id}"
    return busy(mother, force, approved_ids, whole_day, attempt) unless lock_manager.lock(lock_key, LOCK_TTL)

    begin
      Crm::ReactivationPlan.run!(mother, force: force, approved_ids: approved_ids, whole_day: whole_day)
    rescue StandardError => e
      Rails.logger.error "[Crm::ReactivationPlanJob] plano #{mother.id}: #{e.message}"
      Crm::ReactivationPlan.note!(mother, 'last_error' => e.message.to_s.first(200), 'last_check_at' => Time.current.iso8601)
    ensure
      Crm::ReactivationPlan.note!(mother, 'queued_batch' => nil) if approved_ids
      lock_manager.unlock(lock_key)
    end
  end

  # o robô da hora não precisa insistir (volta na hora seguinte); o lote que a
  # pessoa APROVOU não pode sumir: espera a trava soltar e tenta de novo
  def busy(mother, force, approved_ids, whole_day, attempt)
    return if approved_ids.nil?

    if attempt >= MAX_ATTEMPTS
      Crm::ReactivationPlan.note!(mother, 'queued_batch' => nil, 'last_check_at' => Time.current.iso8601,
                                          'last_error' => 'O lote aprovado não saiu: outra rodada do plano estava em andamento. Aprove de novo.')
      return
    end
    self.class.set(wait: RETRY_WAIT).perform_later(mother.id, force: force, approved_ids: approved_ids, whole_day: whole_day, attempt: attempt + 1)
  end
end
