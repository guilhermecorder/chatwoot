# ⏳ Cards parados — passos reais de app/jobs/crm_stalled_cards_job.rb (item 170):
# acha os cards parados e enfileira a automação de coluna "card parado".
class Crm::FlowMap::Flows::StalledCards
  FLOW = Crm::FlowMap::Flow.define(:stalled_cards) do # rubocop:disable Metrics/BlockLength
    name 'Cards parados'
    group 'Gestão e evolução do time'
    icon 'i-lucide-hourglass'
    color '#B45309'
    what 'vigia os cards parados nas colunas e dispara as automações de "card parado"'
    config tab: 'programacao'
    trigger :cron, 'A cada 30 min (CrmStalledCardsJob)'
    jobs 'CrmStalledCardsJob'

    node :automacao, 'Para cada automação "card parado" ativa', kind: :loop
    node :atraso, 'Atraso configurado > 0?', kind: :decision
    node :parados, 'Cards parados na coluna há ≥ atraso'
    node :card, 'Para cada card', kind: :loop
    node :disparou, 'Já disparou desde que o card entrou?', kind: :decision
    node :lock, 'Trava de 6 h por card'
    node :enfileira, 'Enfileira a automação de coluna', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :automacao
    edge :automacao, :atraso
    edge :atraso, :fim, 'não'
    edge :atraso, :parados, 'sim'
    edge :parados, :card
    edge :card, :disparou
    edge :disparou, :fim, 'sim'
    edge :disparou, :lock, 'não'
    edge :lock, :enfileira
    edge :enfileira, :fim

    live do |account|
      autos = Crm::Automation.joins(stage: :pipeline)
                             .where(crm_pipelines: { account_id: account.id }, trigger_type: 'card_stalled')
      active = autos.where(active: true)
      logs = Crm::AutomationLog.where(automation_id: autos.select(:id))
      {
        enabled: active.exists?,
        last_run_at: logs.maximum(:fired_at),
        counters: {
          'gatilhos de card parado' => active.count,
          'disparos hoje' => logs.where(status: 'fired', fired_at: today_range).count
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
