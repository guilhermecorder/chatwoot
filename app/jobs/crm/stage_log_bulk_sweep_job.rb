# 🧹 item 309: toda madrugada, as cargas em massa dos últimos 3 dias saem dos
# indicadores de "Entrou em…" sozinhas (importação, mover em lote, sincronização,
# script) — sem depender de alguém lembrar de rodar o rake.
class Crm::StageLogBulkSweepJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      marked = Crm::StageLogBulk.mark!(account, since: 3.days.ago)
      Rails.logger.info "[CEVICO carga em massa] conta #{account.id}: #{marked} entradas fora dos indicadores" if marked.positive?
    rescue StandardError => e
      Rails.logger.error "[CEVICO carga em massa] conta #{account.id}: #{e.message}"
    end
  end
end
