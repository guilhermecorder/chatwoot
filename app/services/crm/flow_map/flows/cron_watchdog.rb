# 🚨 Vigia dos robôs (Rodada 6 "Rede de segurança", achado #217) — passos reais
# de app/jobs/crm/cron_watchdog_job.rb + sidekiq_heartbeat_job.rb (Crm::CronHealth).
class Crm::FlowMap::Flows::CronWatchdog
  FLOW = Crm::FlowMap::Flow.define(:cron_watchdog) do # rubocop:disable Metrics/BlockLength
    name 'Vigia dos robôs'
    group 'Infraestrutura'
    icon 'i-lucide-heart-pulse'
    color '#DC2626'
    what 'confere a cada 10 min se os robôs CEVICO rodaram e avisa o administrador quando um parou ou deu erro'
    config tab: 'programacao'
    trigger :cron, 'A cada 10 min (sinal de vida da fila: a cada 1 min)'
    jobs 'Crm::CronWatchdogJob', 'Crm::SidekiqHeartbeatJob'

    node :sinal, 'Lê o sinal de vida de cada robô (Redis)'
    node :problema, 'Algum robô parado ou com erro 2× seguidas?', kind: :decision
    node :repetido, 'Já avisou deste problema nas últimas 12 h?', kind: :decision
    node :marca, 'Grava a marca "já avisei" (antes de avisar)'
    node :avisa, 'Radar + tarefa 🔴 + e-mail para o administrador', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :sinal
    edge :sinal, :problema
    edge :problema, :fim, 'tudo rodando'
    edge :problema, :repetido, 'sim'
    edge :repetido, :fim, 'sim (espera)'
    edge :repetido, :marca, 'não'
    edge :marca, :avisa
    edge :avisa, :fim

    live do |_account|
      state = ai['cron_health'] || {}
      incidents = state['incidents'].is_a?(Hash) ? state['incidents'] : {}
      {
        enabled: true,
        last_run_at: state['checked_at'],
        counters: { 'robôs com problema agora' => incidents.size },
        note: state['checked_at'].present? ? nil : 'o vigia ainda não rodou nesta conta'
      }
    end
  end

  def self.flow
    FLOW
  end
end
