# ⚡ Automações de coluna — passos reais de app/jobs/crm_automation_fire_job.rb
# e app/models/crm/automation.rb (item 170). O gatilho "card parado" tem
# fluxo próprio (stalled_cards) e cai aqui na hora de disparar.
class Crm::FlowMap::Flows::ColumnAutomations
  FLOW = Crm::FlowMap::Flow.define(:column_automations) do # rubocop:disable Metrics/BlockLength
    name 'Automações de coluna'
    group 'Vendas e fechamento'
    icon 'i-lucide-zap'
    color '#D97706'
    what 'gatilhos das colunas do CRM (entrou, saiu, etiqueta, mensagem, parado) disparam ações'
    config tab: 'programacao'
    trigger :event, 'Card entrou/saiu, etiqueta, mensagem, valor ou card parado'
    jobs 'CrmAutomationFireJob'

    node :ativa, 'Automação ativa?', kind: :decision
    node :contato, 'Contato resolvido na conta?', kind: :decision
    node :saiu, 'Tinha atraso e o card já saiu da coluna?', kind: :decision
    node :caixa, 'Caixa de chegada bate?', kind: :decision
    node :etiqueta, 'Etiqueta exigida presente?', kind: :decision
    node :payload, 'Monta o payload do contato'
    node :acao, 'Qual ação?', kind: :decision
    node :webhook, 'Webhook / fluxo N8N', kind: :external
    node :mover, 'Aplicar etiqueta / mover card'
    node :avisar, 'Avisar o time / linha do tempo', kind: :output
    node :ads, 'Evento Meta Ads / conversão Google Ads', kind: :external
    node :enviar, 'Enviar formulário / modelo (cooldown 7 d)', kind: :output
    node :ia, 'Chamar agente de IA (analisar, agendar, fechamento, NPS)', kind: :ai
    node :valor, 'Definir valor do card'
    node :trilha, 'Trilha no contato (60) + registro fired/failed', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ativa
    edge :ativa, :fim, 'não'
    edge :ativa, :contato, 'sim'
    edge :contato, :fim, 'não'
    edge :contato, :saiu, 'sim'
    edge :saiu, :fim, 'sim'
    edge :saiu, :caixa, 'não'
    edge :caixa, :fim, 'não'
    edge :caixa, :etiqueta, 'sim'
    edge :etiqueta, :fim, 'não'
    edge :etiqueta, :payload, 'sim'
    edge :payload, :acao
    edge :acao, :webhook, 'webhook'
    edge :acao, :mover, 'etiqueta / mover'
    edge :acao, :avisar, 'avisar'
    edge :acao, :ads, 'anúncios'
    edge :acao, :enviar, 'enviar'
    edge :acao, :ia, 'IA'
    edge :acao, :valor, 'valor'
    edge :webhook, :trilha
    edge :mover, :trilha
    edge :avisar, :trilha
    edge :ads, :trilha
    edge :enviar, :trilha
    edge :ia, :trilha
    edge :valor, :trilha
    edge :trilha, :fim

    live do |account|
      autos = Crm::Automation.joins(stage: :pipeline).where(crm_pipelines: { account_id: account.id })
      logs = Crm::AutomationLog.where(automation_id: autos.select(:id))
      active = autos.where(active: true).count
      {
        enabled: active.positive?,
        last_run_at: logs.maximum(:fired_at),
        counters: {
          'automações ativas' => active,
          'disparos hoje' => logs.where(status: 'fired', fired_at: today_range).count,
          'falhas hoje' => logs.where(status: 'failed', updated_at: today_range).count
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
