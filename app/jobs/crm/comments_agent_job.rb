# Roda o Respondedor de Comentários (IG/FB) para as contas com o agente
# LIGADO e token da Página configurado. Cron a cada 5 minutos.
#
# 🔒 Rodada 4 da auditoria: trava por conta. Uma rodada pode passar de 5 min
# (Meta lenta + IA); sem a trava, a rodada seguinte começaria junto e as duas
# poderiam responder o mesmo comentário em público. Com a trava ocupada, a
# rodada nova só registra no log e deixa a que está rodando terminar.
class Crm::CommentsAgentJob < ApplicationJob
  queue_as :low

  LOCK_TTL = 20.minutes # folga: se o processo morrer, a trava se solta sozinha

  def self.lock_key(account_id)
    "CRM_COMMENTS_AGENT_LOCK:#{account_id}"
  end

  def perform
    CrmSetting.find_each do |settings|
      agent = ((settings.ai_config || {})['agents'] || {})['comments'] || {}
      next unless agent['enabled'] == true
      next if agent['page_access_token'].blank?

      run_locked(settings)
    rescue StandardError => e
      Rails.logger.error "[Crm::CommentsAgent] account=#{settings.account_id} falhou: #{e.message}"
    end
  end

  private

  def run_locked(settings)
    lock_manager = Redis::LockManager.new
    key = self.class.lock_key(settings.account_id)
    unless lock_manager.lock(key, LOCK_TTL)
      Rails.logger.info "[Crm::CommentsAgent] account=#{settings.account_id} já tem uma rodada em andamento — pulando"
      return
    end

    begin
      result = Crm::CommentsAgentService.new(settings.account).call
      Rails.logger.info "[Crm::CommentsAgent] account=#{settings.account_id} #{result.inspect}"
    ensure
      lock_manager.unlock(key)
    end
  end
end
