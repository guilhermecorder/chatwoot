# 💼 Consultor Comercial — passos reais de app/services/crm/sales_coach_service.rb
# e objection_map_service.rb (item 170).
class Crm::FlowMap::Flows::Sales
  FLOW = Crm::FlowMap::Flow.define(:sales) do # rubocop:disable Metrics/BlockLength
    name 'Consultor Comercial'
    group 'Vendas e fechamento'
    icon 'i-lucide-briefcase'
    color '#065F46'
    what 'analisa objeções e gera insights de vendas para a gestão'
    config tab: 'agentes', anchor: 'sales'
    trigger :manual, 'Botões: ajuda com objeção, insights, mapa de objeções'
    jobs 'Crm::SalesInsightsJob', 'Crm::ObjectionMapJob'

    node :ligado, 'Agente ligado?', kind: :decision
    node :tipo, 'Qual pedido?', kind: :decision
    node :objecao, 'IA sugere a resposta à objeção (ao vivo)', kind: :ai
    node :fechamentos, 'Existem fechamentos registrados?', kind: :decision
    node :aviso, 'Aviso: ainda sem fechamentos', kind: :output
    node :insights, 'IA escreve os insights de vendas', kind: :ai
    node :mapa, 'IA monta o mapa de objeções (admin)', kind: :ai
    node :grava, 'Guarda em insights / mapa de objeções', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :tipo, 'sim'
    edge :tipo, :objecao, 'objeção'
    edge :objecao, :fim
    edge :tipo, :fechamentos, 'insights'
    edge :fechamentos, :aviso, 'não'
    edge :aviso, :fim
    edge :fechamentos, :insights, 'sim'
    edge :insights, :grava
    edge :tipo, :mapa, 'mapa'
    edge :mapa, :grava
    edge :grava, :fim

    live do |account|
      cfg = ai(account).dig('agents', 'sales') || {}
      {
        enabled: agent_enabled?(account, 'sales'),
        last_run_at: usage_last(account, 'sales'),
        counters: {
          'insights' => cfg['insights'].present? ? 'gerados' : 'ainda não',
          'mapa de objeções' => cfg['objection_map'].present? ? 'pronto' : 'ainda não',
          'pedidos (30 dias)' => usage_count(account, 'sales', 30.days.ago)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
