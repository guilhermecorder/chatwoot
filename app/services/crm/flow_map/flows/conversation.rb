# 🧠 Analista de Conversas — passos reais de app/services/crm/conversation_insight_service.rb (item 170).
class Crm::FlowMap::Flows::Conversation
  FLOW = Crm::FlowMap::Flow.define(:conversation) do # rubocop:disable Metrics/BlockLength
    name 'Analista de Conversas'
    group 'Atendimento ao paciente'
    icon 'i-lucide-messages-square'
    color '#7C3AED'
    what 'lê a conversa, mede interesse e sugere frases para a atendente'
    config tab: 'agentes', anchor: 'conversation'
    trigger :manual, 'Botão "Analisar com IA" ou ação de coluna'

    node :ligado, 'Agente ligado?', kind: :decision
    node :chave, 'Sem chave ou pausado?', kind: :decision
    node :vazia, 'Transcrição vazia?', kind: :decision
    node :erro, 'Aviso de erro na tela', kind: :output
    node :ia, 'IA: interesse, resumo, próximo passo, etapa, frases', kind: :ai
    node :grava, 'Análise no balão do CRM', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :chave, 'sim'
    edge :chave, :erro, 'sim'
    edge :chave, :vazia, 'não'
    edge :vazia, :erro, 'sim'
    edge :erro, :fim
    edge :vazia, :ia, 'não'
    edge :ia, :grava
    edge :grava, :fim

    live do |account|
      {
        enabled: agent_enabled?(account, 'conversation'),
        last_run_at: usage_last(account, 'conversation'),
        counters: { 'análises (7 dias)' => usage_count(account, 'conversation', 7.days.ago) }
      }
    end
  end

  def self.flow
    FLOW
  end
end
