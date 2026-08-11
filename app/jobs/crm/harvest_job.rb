# 🌾 Cron HORÁRIO da Colheitadeira (item 128), das 12h às 20h UTC (9h–17h SP):
#  1. No dia configurado do mês (padrão dia 1), gera a PRÉVIA da colheita e
#     abre tarefa de aprovação para o admin (uma vez por mês).
#  2. Com a colheita APROVADA, envia o próximo lote respeitando o teto diário
#     (anti-bloqueio) — o expediente já é garantido pelo horário do cron.
# Modo pontual (botões da tela): perform(account_id, 'preview' | 'batch').
class Crm::HarvestJob < ApplicationJob
  queue_as :low

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  HOURLY_SLICE = 12 # lotes pequenos por hora — espalha o dia, não rajada

  def perform(account_id = nil, mode = nil)
    return run_one(Account.find(account_id), mode) if account_id

    lock_manager = Redis::LockManager.new
    return unless lock_manager.lock('CRM_HARVEST_JOB_LOCK', 30.minutes)

    begin
      CrmSetting.find_each do |settings|
        cfg = ((settings.ai_config || {})['agents'] || {})['harvest'] || {}
        next unless cfg['enabled'] == true

        service = Crm::HarvestService.new(account: settings.account)
        maybe_generate(service, cfg)
        service.send_batch!(max_now: HOURLY_SLICE)
      rescue StandardError => e
        Rails.logger.error "[Colheitadeira] conta=#{settings.account_id} falhou: #{e.message}"
      end
    ensure
      lock_manager.unlock('CRM_HARVEST_JOB_LOCK')
    end
  end

  private

  def run_one(account, mode)
    service = Crm::HarvestService.new(account: account)
    case mode
    when 'preview' then service.generate_preview!
    when 'batch' then service.send_batch!
    end
  end

  # prévia nova quando: chegou o dia do mês configurado E o estado ainda é do
  # mês passado (ou não existe). Rodadas seguintes do dia não regeram (idempotente).
  def maybe_generate(service, cfg)
    day = (cfg['day_of_month'].presence || Crm::HarvestService::DEFAULT_DAY_OF_MONTH).to_i.clamp(1, 28)
    return if TZ.today.day < day
    return if service.state['month_key'] == service.month_key

    service.generate_preview!
  end
end
