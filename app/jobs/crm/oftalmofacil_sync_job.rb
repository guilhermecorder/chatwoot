# 🏥 Sincronização periódica com o OftalmoFácil (item 157): a cada 15 min,
# toda conta com a conexão CONFIGURADA e LIGADA puxa o que mudou lá desde o
# último cursor e trata (paciente, card, valor, etiquetas). Guarda o cursor
# e o resumo da última rodada em agenda_config.oftalmofacil pra tela mostrar.
# Também é o que o botão "Sincronizar agora" do card chama (perform_later).
class Crm::OftalmofacilSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id = nil, full: false) # rubocop:disable Metrics/CyclomaticComplexity
    scope = account_id ? CrmSetting.where(account_id: account_id) : CrmSetting.all
    scope.find_each do |settings|
      cfg = settings.agenda_config&.dig('oftalmofacil') || {}
      next unless cfg['enabled'] == true || account_id.present?
      next unless Crm::OftalmofacilSyncService.configured?(cfg)

      run_for(settings, cfg, full)
    rescue StandardError => e
      Rails.logger.error "[OftalmoFácil sync] conta #{settings.account_id}: #{e.message}"
    end
  end

  private

  def run_for(settings, cfg, full) # rubocop:disable Metrics/AbcSize
    service = Crm::OftalmofacilSyncService.new(account: settings.account, config: cfg,
                                               since: full ? nil : :cursor, silent: full ? true : nil)
    result = service.call

    # cursor + resumo da rodada (relê a config fresca pra não sobrescrever
    # o que o admin salvou enquanto o job rodava)
    settings.reload
    agenda = settings.agenda_config || {}
    of = agenda['oftalmofacil'] || {}
    of['last_sync_at'] = result.cursor if result.cursor.present?
    of['last_run_at'] = Time.current.iso8601
    of['last_result'] = {
      'pulled' => result.pulled, 'created_contacts' => result.created_contacts, 'moved' => result.moved,
      'ahead' => result.ahead, 'labeled' => result.labeled, 'errors' => result.errors.first(5),
      'error_count' => result.errors.size
    }
    agenda['oftalmofacil'] = of
    settings.update!(agenda_config: agenda)
  end
end
