# 🩺 Atendente de Pós-operatório (WhatsApp, item 251) — mesmo motor dos
# respondedores (app/jobs/crm/responder_agent_job.rb): 24h, orientações
# oficiais do pós-op, tarefa para a equipe em tudo que sai do simples.
class Crm::FlowMap::Flows::AtendentePosOp
  FLOW = Crm::FlowMap::Flow.define(:atendente_pos_op) do # rubocop:disable Metrics/BlockLength
    name 'Atendente de Pós-operatório'
    group 'Atendimento ao paciente'
    icon 'i-lucide-heart-pulse'
    color '#BE123C'
    what 'responde 24h as dúvidas simples de quem operou (colírio, ardência, banho, maquiagem) e abre tarefa para a equipe no resto'
    config tab: 'agentes', anchor: 'atendente_pos_op'
    trigger :event, 'Mensagem do paciente: coluna dele ou cirurgia recente'
    jobs 'Crm::ResponderAgentJob'

    node :ligado, 'Agente ligado, caixa e coluna dele (ou cirurgia recente)?', kind: :decision
    node :ultima, 'Ainda é a última mensagem?', kind: :decision
    node :modo, 'Modo: sombra ou ao vivo?', kind: :decision
    node :contexto, 'Contexto: cirurgia (data, procedimento, dias) e retorno'
    node :ia, 'IA lê Roteiro + orientações do pós-op (até 2 balões)', kind: :ai
    node :nota, 'Nota interna 🕶️ teria respondido (nada ao paciente)', kind: :output
    node :simples, 'Dúvida simples das orientações oficiais?', kind: :decision
    node :responde, 'Responde com o texto oficial (colírio, ardência, banho…)', kind: :output
    node :tarefa, 'Abre tarefa para a responsável (Meu Painel)'
    node :alerta, 'Sintoma de alerta?', kind: :decision
    node :humano, 'Orienta pronto atendimento, avisa a equipe e pausa', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :ultima, 'sim'
    edge :ultima, :fim, 'não'
    edge :ultima, :modo, 'sim'
    edge :modo, :contexto
    edge :contexto, :ia
    edge :ia, :nota, 'sombra'
    edge :nota, :fim
    edge :ia, :simples, 'ao vivo'
    edge :simples, :responde, 'sim'
    edge :responde, :fim
    edge :simples, :alerta, 'não'
    edge :alerta, :tarefa, 'não (dúvida do caso, documento)'
    edge :tarefa, :fim
    edge :alerta, :humano, 'sim (dor forte, perda de visão…)'
    edge :humano, :tarefa

    live do |account|
      cfg = ai(account).dig('agents', 'atendente_pos_op') || {}
      events = Array(ai(account).dig('atendente_pos_op_state', 'events'))
      {
        enabled: agent_enabled?(account, 'atendente_pos_op') && Array(cfg['inbox_ids']).any?,
        last_run_at: last_at(events) || usage_last(account, 'atendente_pos_op'),
        counters: {
          'modo' => (Crm::ResponderAgentJob.live_mode?(cfg) ? 'ao vivo' : 'sombra'),
          'caixas em que atende' => Array(cfg['inbox_ids']).size,
          'colunas dele' => Array(cfg['stage_ids']).size,
          'cirurgia recente (dias)' => cfg['recent_surgery_days'].to_i,
          'notas de sombra hoje' => count_today(events),
          'respostas (7 dias)' => usage_count(account, 'atendente_pos_op', 7.days.ago)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
