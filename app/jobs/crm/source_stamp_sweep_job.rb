# 🏷️ item 322: toda madrugada, o que ainda estiver SEM carimbo de fonte é
# carimbado pelas regras de hoje (Crm::SourceBackfill) — o passado na primeira
# noite depois do deploy, e depois só o que escapou (paciente que nasceu sem
# nenhuma evidência de fonte). Não reescreve nada já carimbado.
class Crm::SourceStampSweepJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next unless CrmSetting.exists?(account_id: account.id)

      done = Crm::SourceBackfill.run!(account)
      total = done.values.sum { |by_source| by_source.values.sum }
      Rails.logger.info "[carimbo] conta #{account.id}: #{total} registros carimbados #{done.to_json}" if total.positive?
    rescue StandardError => e
      Rails.logger.error "[carimbo] conta #{account.id}: #{e.class}: #{e.message}"
    end
  end
end
