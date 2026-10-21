# 📋 Analista de Formulários — passos reais de app/services/crm/form_insight_service.rb (item 170).
class Crm::FlowMap::Flows::Form
  FLOW = Crm::FlowMap::Flow.define(:form) do
    name 'Analista de Formulários'
    group 'Vendas e fechamento'
    icon 'i-lucide-clipboard-list'
    color '#0E7490'
    what 'resume as respostas dos formulários no card do paciente'
    config tab: 'agentes', anchor: 'form'
    trigger :manual, 'Botão no hub de Formulários'

    node :ligado, 'Agente ligado?', kind: :decision
    node :respostas, 'Formulário tem respostas?', kind: :decision
    node :erro, 'Aviso: sem respostas', kind: :output
    node :ia, 'IA resume até 300 respostas', kind: :ai
    node :grava, 'Resumo gravado no formulário', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :respostas, 'sim'
    edge :respostas, :erro, 'não'
    edge :erro, :fim
    edge :respostas, :ia, 'sim'
    edge :ia, :grava
    edge :grava, :fim

    live do |account|
      {
        enabled: agent_enabled?(account, 'form'),
        last_run_at: usage_last(account, 'form'),
        counters: { 'resumos (30 dias)' => usage_count(account, 'form', 30.days.ago) }
      }
    end
  end

  def self.flow
    FLOW
  end
end
