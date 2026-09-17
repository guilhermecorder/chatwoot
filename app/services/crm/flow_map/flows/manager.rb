# 📊 Gestor Autônomo — passos reais de app/jobs/crm/auto_manager_job.rb e auto_manager_service.rb (item 170).
class Crm::FlowMap::Flows::Manager
  FLOW = Crm::FlowMap::Flow.define(:manager) do # rubocop:disable Metrics/BlockLength
    name 'Gestor Autônomo'
    group 'Gestão e evolução do time'
    icon 'i-lucide-gauge'
    color '#0F5FA6'
    what 'lê o funil todo dia, abre tarefas nos desvios e escreve o briefing'
    config tab: 'agentes', anchor: 'manager'
    trigger :cron, 'Dias úteis 08:10 (Crm::AutoManagerJob) ou "Rodar agora"'
    jobs 'Crm::AutoManagerJob'

    node :ligado, 'Agente ligado?', kind: :decision
    node :hoje, 'Já rodou hoje (sem forçar)?', kind: :decision
    node :historico, 'Tem 4 semanas de histórico?', kind: :decision
    node :indicador, 'Para cada indicador do funil', kind: :loop
    node :baseline, 'Média zero ou volume abaixo do mínimo?', kind: :decision
    node :compara, 'Pior semana (projetada / fechada) vs média'
    node :queda, 'Queda maior que o limite (25%)?', kind: :decision
    node :achado, 'Vira achado'
    node :tarefas, 'Tarefas 📊 Gestor (3 piores, sem duplicar)', kind: :output
    node :ia, 'IA escreve o briefing do dia', kind: :ai
    node :grava, 'Grava o estado (achados, briefing)', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :hoje, 'sim'
    edge :hoje, :fim, 'sim'
    edge :hoje, :historico, 'não'
    edge :historico, :fim, 'não'
    edge :historico, :indicador, 'sim'
    edge :indicador, :baseline
    edge :baseline, :indicador, 'sim (pula)'
    edge :baseline, :compara, 'não'
    edge :compara, :queda
    edge :queda, :indicador, 'não'
    edge :queda, :achado, 'sim'
    edge :achado, :tarefas
    edge :tarefas, :ia
    edge :ia, :grava
    edge :grava, :fim

    live do |account|
      st = ai(account)['manager_state'] || {}
      opened = st['tasks_opened']
      {
        enabled: agent_enabled?(account, 'manager'),
        last_run_at: st['last_run_at'],
        counters: {
          'achados' => Array(st['findings']).size,
          'tarefas abertas' => opened.respond_to?(:size) ? opened.size : opened.to_i,
          'último dia' => st['last_run_date'].presence || '—'
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
