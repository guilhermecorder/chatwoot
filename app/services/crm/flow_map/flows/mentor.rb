# 🎓 Mentor do Time — passos reais de app/jobs/crm/weekly_mentor_job.rb,
# monthly_mentor_job.rb e weekly_mentor_service.rb (item 170).
class Crm::FlowMap::Flows::Mentor
  FLOW = Crm::FlowMap::Flow.define(:mentor) do # rubocop:disable Metrics/BlockLength
    name 'Mentor do Time'
    group 'Gestão e evolução do time'
    icon 'i-lucide-graduation-cap'
    color '#0F766E'
    what 'escreve o feedback semanal e mensal de cada pessoa do time'
    config tab: 'agentes', anchor: 'mentor'
    trigger :cron, 'Segunda 08h (semanal) e dia 1 08:30 (mensal), ou botão'
    jobs 'Crm::WeeklyMentorJob', 'Crm::MonthlyMentorJob'

    node :ligado, 'Agente ligado e com chave?', kind: :decision
    node :periodo, 'Período: semana/mês fechado (botão: últimos 7 dias)'
    node :metricas, 'Métricas por pessoa: resposta, meta, resolvidas, tarefas'
    node :uso, 'Pessoa usou o sistema no período?', kind: :decision
    node :fora, 'Fica de fora'
    node :inativo, 'Time inteiro inativo?', kind: :decision
    node :mediana, 'Mediana do time + meta do mês'
    node :pessoa, 'Para cada pessoa', kind: :loop
    node :ia, 'IA escreve o feedback (1 chamada por pessoa)', kind: :ai
    node :erro, 'Erro na IA?', kind: :decision
    node :grava, 'Feedback gravado (aparece no Meu Painel)', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :periodo, 'sim'
    edge :periodo, :metricas
    edge :metricas, :uso
    edge :uso, :fora, 'não'
    edge :fora, :inativo
    edge :uso, :inativo, 'sim'
    edge :inativo, :fim, 'sim'
    edge :inativo, :mediana, 'não'
    edge :mediana, :pessoa
    edge :pessoa, :ia
    edge :ia, :erro
    edge :erro, :fim, 'sim (não grava)'
    edge :erro, :grava, 'não'
    edge :grava, :fim

    live do |account|
      feedbacks = Crm::WeeklyFeedback.where(account_id: account.id)
      recent = feedbacks.where(created_at: 30.days.ago..)
      {
        enabled: agent_enabled?(account, 'mentor'),
        last_run_at: feedbacks.maximum(:created_at),
        counters: {
          'feedbacks (30 dias)' => recent.count,
          'semanais' => recent.where(cadence: 'weekly').count,
          'mensais' => recent.where(cadence: 'monthly').count
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
