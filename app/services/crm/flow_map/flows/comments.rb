# 💬 Respondedor de Comentários — passos reais de app/jobs/crm/comments_agent_job.rb
# e comments_agent_service.rb (item 170).
class Crm::FlowMap::Flows::Comments
  FLOW = Crm::FlowMap::Flow.define(:comments) do # rubocop:disable Metrics/BlockLength
    name 'Respondedor de Comentários'
    group 'Atendimento ao paciente'
    icon 'i-lucide-message-circle-heart'
    color '#E1306C'
    what 'responde comentários públicos no Instagram e Facebook'
    config tab: 'agentes', anchor: 'comments'
    trigger :cron, 'A cada 5 min (Crm::CommentsAgentJob)'
    jobs 'Crm::CommentsAgentJob'

    node :ligado, 'Agente ligado com token da página?', kind: :decision
    node :chave, 'Sem token, sem chave ou pausado?', kind: :decision
    node :erro, 'Registra o erro no estado', kind: :output
    node :horario, 'Entre 07h e 22h (SP)?', kind: :decision
    node :poda, 'Poda a memória (30 dias)'
    node :coleta, 'Coleta comentários (10 mídias IG + 10 posts FB)'
    node :cada, 'Para cada comentário (teto 10/rodada)', kind: :loop
    node :tratado, 'Já tratado?', kind: :decision
    node :ia, 'IA decide: responder, humano ou ignorar', kind: :ai
    node :marca, 'Marca como tratado ANTES de responder'
    node :decisao, 'Decisão da IA', kind: :decision
    node :post, 'Responde no Instagram/Facebook (Graph)', kind: :external
    node :humano, 'Deixa para um humano responder', kind: :output
    node :ignora, 'Ignora o comentário'
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :chave, 'sim'
    edge :chave, :erro, 'sim'
    edge :erro, :fim
    edge :chave, :horario, 'não'
    edge :horario, :fim, 'não'
    edge :horario, :poda, 'sim'
    edge :poda, :coleta
    edge :coleta, :cada
    edge :cada, :tratado
    edge :tratado, :cada, 'sim'
    edge :tratado, :ia, 'não'
    edge :ia, :marca
    edge :marca, :decisao
    edge :decisao, :post, 'responder'
    edge :decisao, :humano, 'humano'
    edge :decisao, :ignora, 'ignorar'
    edge :post, :fim
    edge :humano, :fim
    edge :ignora, :fim

    live do |account|
      cfg = ai(account).dig('agents', 'comments') || {}
      st = ai(account)['comments_state'] || {}
      handled = st['handled']
      {
        enabled: agent_enabled?(account, 'comments') && cfg['page_access_token'].present?,
        last_run_at: st['last_run_at'],
        counters: {
          'comentários na memória' => handled.respond_to?(:size) ? handled.size : 0,
          'eventos hoje' => count_today(st['events']),
          'respostas (7 dias)' => usage_count(account, 'comments', 7.days.ago)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
