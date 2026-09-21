# 🗣️ Atendente de Agendamento (WhatsApp) — passos reais de
# app/jobs/crm/responder_agent_job.rb e responder_agent_service.rb (rodada 188).
class Crm::FlowMap::Flows::AtendentePos
  FLOW = Crm::FlowMap::Flow.define(:atendente_pos) do # rubocop:disable Metrics/BlockLength
    name 'Atendente Pós-agendamento'
    group 'Atendimento ao paciente'
    icon 'i-lucide-life-buoy'
    color '#0F5FA6'
    what 'suporte no WhatsApp a quem já marcou: dúvidas, remarcar e cancelar (Roteiro CEVICO + agenda viva)'
    config tab: 'agentes', anchor: 'atendente_pos'
    trigger :event, 'Mensagem do paciente na caixa e coluna dele (espera 12 s)'
    jobs 'Crm::ResponderAgentJob'

    node :ligado, 'Agente ligado, caixa e coluna dele?', kind: :decision
    node :ultima, 'Ainda é a última mensagem?', kind: :decision
    node :modo, 'Modo: sombra ou ao vivo?', kind: :decision
    node :teto_sombra, 'Passou do teto de conversas/dia da sombra?', kind: :decision
    node :contexto, 'Contexto: agora, contato, coluna, vagas, consulta futura'
    node :ia, 'IA lê Roteiro + etapa e decide (até 3 msgs)', kind: :ai
    node :nota, 'Nota interna 🕶️ teria respondido (nada ao paciente)', kind: :output
    node :pausado, 'Humano assumiu (pausado)?', kind: :decision
    node :agendar, 'IA pediu para agendar?', kind: :decision
    node :vaga, 'Trava a vaga + confere + grava na Agenda', kind: :decision
    node :outra, 'Diz que a vaga foi preenchida e pede outra', kind: :output
    node :envia, 'Envia até 3 msgs (😊 só depois de gravar)', kind: :output
    node :move, 'Remarca ou cancela a consulta na Agenda'
    node :humano, 'IA chamou humano?', kind: :decision
    node :pausa, 'Pausa o agente nesta conversa'
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :ultima, 'sim'
    edge :ultima, :fim, 'não'
    edge :ultima, :modo, 'sim'
    edge :modo, :teto_sombra, 'sombra'
    edge :teto_sombra, :fim, 'sim'
    edge :teto_sombra, :contexto, 'não'
    edge :modo, :pausado, 'ao vivo'
    edge :pausado, :fim, 'sim'
    edge :pausado, :contexto, 'não'
    edge :contexto, :ia
    edge :ia, :nota, 'sombra'
    edge :nota, :fim
    edge :ia, :agendar, 'ao vivo'
    edge :agendar, :vaga, 'sim'
    edge :vaga, :outra, 'não validou'
    edge :outra, :fim
    edge :vaga, :envia, 'gravou'
    edge :agendar, :envia, 'não'
    edge :envia, :move
    edge :move, :humano
    edge :humano, :pausa, 'sim'
    edge :humano, :fim, 'não'
    edge :pausa, :fim

    live do |account|
      cfg = ai(account).dig('agents', 'atendente_pos') || {}
      events = Array(ai(account).dig('atendente_pos_state', 'events'))
      {
        enabled: agent_enabled?(account, 'atendente_pos') && Array(cfg['inbox_ids']).any?,
        last_run_at: last_at(events) || usage_last(account, 'atendente_pos'),
        counters: {
          'modo' => (Crm::ResponderAgentJob.live_mode?(cfg) ? 'ao vivo' : 'sombra'),
          'caixas em que atende' => Array(cfg['inbox_ids']).size,
          'colunas dele' => Array(cfg['stage_ids']).size + (cfg['no_card'] == true ? 1 : 0),
          'notas de sombra hoje' => count_today(events),
          'leituras (7 dias)' => usage_count(account, 'atendente_pos', 7.days.ago)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
