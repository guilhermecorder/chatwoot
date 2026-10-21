# ⭐ Agente de NPS — passos reais de app/services/crm/nps_service.rb (item 170).
class Crm::FlowMap::Flows::Nps
  FLOW = Crm::FlowMap::Flow.define(:nps) do # rubocop:disable Metrics/BlockLength
    name 'Agente de NPS'
    group 'Atendimento ao paciente'
    icon 'i-lucide-star'
    color '#D97706'
    what 'lê a nota do paciente no pós-operatório e registra o NPS'
    config tab: 'agentes', anchor: 'nps'
    trigger :event, 'Ação de coluna: ler nota de NPS'

    node :ligado, 'Agente ligado?', kind: :decision
    node :chave, 'Sem chave ou pausado?', kind: :decision
    node :erro, 'Registra o erro', kind: :output
    node :ia, 'IA lê a nota 0–10 na conversa', kind: :ai
    node :respondeu, 'Paciente deu a nota?', kind: :decision
    node :etiqueta, 'Etiqueta nps-x-y (troca a anterior)'
    node :grava, 'Grava o NPS no contato', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :chave, 'sim'
    edge :chave, :erro, 'sim'
    edge :erro, :fim
    edge :chave, :ia, 'não'
    edge :ia, :respondeu
    edge :respondeu, :fim, 'não'
    edge :respondeu, :etiqueta, 'sim'
    edge :etiqueta, :grava
    edge :grava, :fim

    live do |account|
      {
        enabled: agent_enabled?(account, 'nps'),
        last_run_at: usage_last(account, 'nps'),
        counters: { 'notas lidas (30 dias)' => usage_count(account, 'nps', 30.days.ago) }
      }
    end
  end

  def self.flow
    FLOW
  end
end
