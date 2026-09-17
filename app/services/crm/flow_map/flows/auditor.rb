# 🎓 Auditor de Conversas — passos reais de app/jobs/crm/conversation_auditor_job.rb
# e conversation_auditor_service.rb (item 170).
class Crm::FlowMap::Flows::Auditor
  FLOW = Crm::FlowMap::Flow.define(:auditor) do # rubocop:disable Metrics/BlockLength
    name 'Auditor de Conversas'
    group 'Gestão e evolução do time'
    icon 'i-lucide-clipboard-check'
    color '#0F766E'
    what 'dá nota diária nas conversas contra o script — coaching contínuo por atendente'
    config tab: 'agentes', anchor: 'auditor'
    trigger :cron, 'Todo dia 07:40 (ConversationAuditorJob) ou "Rodar agora"'
    jobs 'Crm::ConversationAuditorJob'

    node :ligado, 'Agente ligado?', kind: :decision
    node :chave, 'Tem chave da IA?', kind: :decision
    node :auditado, 'Ontem já foi auditado?', kind: :decision
    node :conversas, 'Conversas de ontem com ≥ 2 mensagens (teto 150)'
    node :alguma, 'Alguma conversa?', kind: :decision
    node :semconv, 'Fecha o dia: sem conversas'
    node :lote, 'Lotes de 5 (últimas 30 mensagens)', kind: :loop
    node :ia, 'IA dá nota 0–10, etapa, acerto, falhas', kind: :ai
    node :erro, 'Lote com erro?', kind: :decision
    node :zero, 'Conta 0 e segue'
    node :grava, 'Grava a auditoria na conversa'
    node :agrega, 'Agrega por atendente / dia'
    node :fecha, 'Fecha o dia (poda 30 dias)', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :chave, 'sim'
    edge :chave, :fim, 'não'
    edge :chave, :auditado, 'sim'
    edge :auditado, :fim, 'sim'
    edge :auditado, :conversas, 'não'
    edge :conversas, :alguma
    edge :alguma, :semconv, 'não'
    edge :semconv, :fim
    edge :alguma, :lote, 'sim'
    edge :lote, :ia
    edge :ia, :erro
    edge :erro, :zero, 'sim'
    edge :zero, :agrega
    edge :erro, :grava, 'não'
    edge :grava, :agrega
    edge :agrega, :fecha
    edge :fecha, :fim

    live do |account|
      st = ai(account)['auditor_state'] || {}
      {
        enabled: agent_enabled?(account, 'auditor'),
        last_run_at: st['last_run_at'],
        counters: {
          'dias auditados' => (st['days_done'] || {}).size,
          'atendentes avaliados' => (st['agents'] || {}).size,
          'conversas lidas (7 dias)' => usage_count(account, 'auditor', 7.days.ago)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
