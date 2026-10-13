# 💓 Sinal de vida da fila dos robôs (auditoria 10/2026, achado #217): roda a
# cada 1 min na fila scheduled_jobs (a mesma dos lembretes, quase no fim da
# ordem do Sidekiq) e renova uma chave no Redis. Se o Sidekiq travar ou a fila
# empacar, a chave envelhece: o /health?sidekiq=1 do web responde 503 e o vigia
# (Crm::CronWatchdogJob) avisa o administrador.
class Crm::SidekiqHeartbeatJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Crm::CronHealth.sidekiq_beat!
  end
end
