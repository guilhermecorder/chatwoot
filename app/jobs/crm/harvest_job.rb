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
  LOCK_KEY = 'CRM_HARVEST_JOB_LOCK'.freeze

  # achado #44: os botões da tela ('preview' | 'batch') pegam a MESMA trava do
  # cron. Com a trava ocupada (dois cliques seguidos, clique durante a rodada
  # horária) o pedido é recusado e registrado — a rodada que já está rodando
  # cuida da lista; nenhum lead recebe a mensagem duas vezes. O pedido da tela
  # recusado vira aviso em harvest_state['last_error'] (a tela mostra).
  BUSY_MESSAGE = 'Já tem uma rodada da Colheitadeira em andamento — aguarde ela terminar e tente de novo.'.freeze

  def self.busy?
    Redis::LockManager.new.locked?(LOCK_KEY)
  end

  def perform(account_id = nil, mode = nil)
    lock_manager = Redis::LockManager.new
    return busy(account_id, mode) unless lock_manager.lock(LOCK_KEY, 30.minutes)

    begin
      account_id ? run_one(Account.find(account_id), mode) : run_all
    ensure
      lock_manager.unlock(LOCK_KEY)
    end
  end

  private

  def busy(account_id, mode)
    Rails.logger.info "[Colheitadeira] já tem uma rodada em andamento — pedido ignorado (conta=#{account_id.inspect} modo=#{mode.inspect})"
    return nil unless account_id # cron sem conta: só o log

    # pedido da tela: deixa o aviso no estado para o admin ver (e tentar de novo)
    Crm::HarvestService.new(account: Account.find(account_id)).send(:merge_state, 'last_error' => BUSY_MESSAGE)
    nil
  rescue StandardError => e
    Rails.logger.warn "[Colheitadeira] não deu para registrar o aviso de trava ocupada: #{e.message}"
    nil
  end

  # rodada horária do cron: todas as contas com a Colheitadeira ligada
  def run_all
    CrmSetting.find_each do |settings|
      cfg = ((settings.ai_config || {})['agents'] || {})['harvest'] || {}
      next unless cfg['enabled'] == true

      service = Crm::HarvestService.new(account: settings.account)
      maybe_generate(service, cfg)
      service.send_batch!(max_now: HOURLY_SLICE)
    rescue StandardError => e
      Rails.logger.error "[Colheitadeira] conta=#{settings.account_id} falhou: #{e.message}"
      Crm::CronHealth.failed!('colheita', e, account: settings.account) # 🚨 #217: avisa se repetir
    end
    Crm::CronHealth.ran!('colheita') # 🚨 #217: sinal de vida da rodada do cron
  end

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
