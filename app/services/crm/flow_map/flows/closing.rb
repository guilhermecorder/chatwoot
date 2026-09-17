# 🤝 Monitor de Fechamento — passos reais de app/services/crm/surgery_closing_service.rb (item 170).
class Crm::FlowMap::Flows::Closing
  FLOW = Crm::FlowMap::Flow.define(:closing) do # rubocop:disable Metrics/BlockLength
    name 'Monitor de Fechamento'
    group 'Vendas e fechamento'
    icon 'i-lucide-handshake'
    color '#B8860B'
    what 'detecta fechamentos (valor, pagamento, data) e move o card'
    config tab: 'agentes', anchor: 'closing'
    trigger :event, 'Ação de coluna: detectar fechamento'

    node :ligado, 'Agente ligado?', kind: :decision
    node :chave, 'Sem chave ou pausado?', kind: :decision
    node :erro, 'Registra o erro', kind: :output
    node :ia, 'IA extrai: fechou, valor, pagamento, data', kind: :ai
    node :fechado, 'Fechou?', kind: :decision
    node :grava, 'Grava o fechamento no contato', kind: :output
    node :valor, 'Card sem valor?', kind: :decision
    node :preenche, 'Preenche o valor do card'
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :chave, 'sim'
    edge :chave, :erro, 'sim'
    edge :erro, :fim
    edge :chave, :ia, 'não'
    edge :ia, :fechado
    edge :fechado, :fim, 'não'
    edge :fechado, :grava, 'sim'
    edge :grava, :valor
    edge :valor, :preenche, 'sim'
    edge :preenche, :fim
    edge :valor, :fim, 'não'

    live do |account|
      {
        enabled: agent_enabled?(account, 'closing'),
        last_run_at: usage_last(account, 'closing'),
        counters: { 'leituras (30 dias)' => usage_count(account, 'closing', 30.days.ago) }
      }
    end
  end

  def self.flow
    FLOW
  end
end
