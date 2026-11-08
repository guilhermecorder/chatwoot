# 👓📦 08/11: roda todo dia de manhã (config/schedule.yml) e abre as tarefas
# do vigia dos pedidos em cada loja (Otica::OrderWatch).
class Otica::OrderWatchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    opened = Otica::OrderWatch.run_all!
    Rails.logger.info "[Otica::OrderWatchJob] #{opened} tarefa(s) de pedido aberta(s)"
  end
end
