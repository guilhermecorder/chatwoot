# ✍️ Copywriter — Estúdio de copy (botão Gerar) com os valores da marca (item 170).
class Crm::FlowMap::Flows::Copywriter
  FLOW = Crm::FlowMap::Flow.define(:copywriter) do
    name 'Copywriter'
    group 'Marketing e aquisição'
    icon 'i-lucide-pen-tool'
    color '#5B21B6'
    what 'escreve copies multi-formato com os valores da marca'
    config tab: 'agentes', anchor: 'copywriter'
    trigger :manual, 'Estúdio de copy: botão Gerar'

    node :ligado, 'Agente ligado?', kind: :decision
    node :chave, 'Sem chave ou pausado?', kind: :decision
    node :erro, 'Aviso de erro na tela', kind: :output
    node :brief, 'Briefing + referências da marca'
    node :ia, 'IA escreve a copy no formato pedido', kind: :ai
    node :saida, 'Copy pronta no Estúdio', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :chave, 'sim'
    edge :chave, :erro, 'sim'
    edge :erro, :fim
    edge :chave, :brief, 'não'
    edge :brief, :ia
    edge :ia, :saida
    edge :saida, :fim

    live do |account|
      {
        enabled: agent_enabled?(account, 'copywriter'),
        last_run_at: usage_last(account, 'copywriter'),
        counters: { 'copies (30 dias)' => usage_count(account, 'copywriter', 30.days.ago) }
      }
    end
  end

  def self.flow
    FLOW
  end
end
