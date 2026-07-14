# Roda o Radar de Oportunidades para as contas que têm o agente configurado.
# O cron dispara a cada 10 min, mas o job só age dentro do expediente
# (07:30–18:00 de São Paulo); fora dele roda apenas a cada 4 horas
# (20h, 00h e 04h) — ver Crm::OpportunityRadarService.
class Crm::OpportunityRadarJob < ApplicationJob
  queue_as :low

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  # Sem argumentos = rodada do cron (todas as contas, janela de horário).
  # Com account_id + overrides = radar PONTUAL pedido na tela (roda uma vez).
  def perform(account_id = nil, overrides = {})
    if account_id
      account = Account.find(account_id)
      result = Crm::OpportunityRadarService.new(account: account).call(overrides)
      Rails.logger.info "[Crm::OpportunityRadar] radar pontual account=#{account_id} #{result.inspect}"
      return
    end

    return unless should_run_now?

    CrmSetting.find_each do |settings|
      agents = (settings.ai_config || {})['agents'] || {}
      radar = agents['opportunity'] || {}
      # opt-in explícito: só roda com o interruptor LIGADO (enabled == true)
      next unless radar['enabled'] == true
      # sem vigia (formato novo) nem coluna (formato antigo) = radar desligado
      next if Array(radar['watchers']).empty? && Array(radar['stage_ids']).empty?

      result = Crm::OpportunityRadarService.new(account: settings.account).call
      Rails.logger.info "[Crm::OpportunityRadar] account=#{settings.account_id} #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "[Crm::OpportunityRadar] account=#{settings.account_id} falhou: #{e.message}"
    end
  end

  private

  # expediente (07:30–18:00 SP): toda execução do cron (a cada 10 min).
  # noite/madrugada: só nas janelas de 4 em 4 horas (20h, 00h, 04h).
  def should_run_now?
    now = TZ.now
    minutes = (now.hour * 60) + now.min
    daytime = minutes >= (7 * 60) + 30 && minutes < 18 * 60
    return true if daytime

    [20, 0, 4].include?(now.hour) && now.min < 10
  end
end
