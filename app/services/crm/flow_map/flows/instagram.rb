# 📸 Atendente Direct & Messenger — passos reais de app/jobs/crm/instagram_agent_job.rb
# e instagram_agent_service.rb (item 170).
class Crm::FlowMap::Flows::Instagram
  FLOW = Crm::FlowMap::Flow.define(:instagram) do # rubocop:disable Metrics/BlockLength
    name 'Atendente Instagram'
    group 'Atendimento ao paciente'
    icon 'i-lucide-instagram'
    color '#DB2777'
    what 'responde pacientes no direct (caixas escolhidas) e agenda'
    config tab: 'agentes', anchor: 'instagram'
    trigger :event, 'Mensagem recebida numa caixa escolhida (espera 12 s)'
    jobs 'Crm::InstagramAgentJob'

    node :ligado, 'Agente ligado com caixa escolhida?', kind: :decision
    node :aberta, 'Conversa aberta?', kind: :decision
    node :pausado, 'Humano assumiu (pausado)?', kind: :decision
    node :ultima, 'Ainda é a última mensagem?', kind: :decision
    node :teto, 'Passou de 60 respostas hoje?', kind: :decision
    node :pausa, 'Pausa o agente nesta conversa'
    node :contexto, 'Contexto: data, telefone, horários livres'
    node :ia, 'IA responde (até 3 msgs) e decide', kind: :ai
    node :revalida, 'Chegou mensagem nova enquanto pensava?', kind: :decision
    node :envia, 'Envia até 3 mensagens (1,5 s entre elas)', kind: :output
    node :agendar, 'IA pediu para agendar?', kind: :decision
    node :slot, 'Horário livre (trava + confere)?', kind: :decision
    node :recorder, 'Anota a consulta + telefone + nota'
    node :tarefa, 'Tarefa: confirmar consulta (Instagram)', kind: :output
    node :humano, 'IA chamou humano?', kind: :decision
    node :nota_humano, 'Nota: paciente pediu humano', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :aberta, 'sim'
    edge :aberta, :fim, 'não'
    edge :aberta, :pausado, 'sim'
    edge :pausado, :fim, 'sim'
    edge :pausado, :ultima, 'não'
    edge :ultima, :fim, 'não'
    edge :ultima, :teto, 'sim'
    edge :teto, :pausa, 'sim'
    edge :teto, :contexto, 'não'
    edge :contexto, :ia
    edge :ia, :revalida
    edge :revalida, :fim, 'sim'
    edge :revalida, :envia, 'não'
    edge :envia, :agendar
    edge :agendar, :slot, 'sim'
    edge :slot, :recorder, 'sim'
    edge :slot, :tarefa, 'não'
    edge :recorder, :pausa
    edge :tarefa, :pausa
    edge :agendar, :humano, 'não'
    edge :humano, :nota_humano, 'sim'
    edge :nota_humano, :pausa
    edge :humano, :fim, 'não'
    edge :pausa, :fim

    live do |account|
      cfg = ai(account).dig('agents', 'instagram') || {}
      events = Array(ai(account).dig('instagram_state', 'events'))
      {
        enabled: agent_enabled?(account, 'instagram') && Array(cfg['inbox_ids']).any?,
        last_run_at: last_at(events) || usage_last(account, 'instagram'),
        counters: {
          'caixas em que atende' => Array(cfg['inbox_ids']).size,
          'eventos hoje' => count_today(events),
          'respostas (7 dias)' => usage_count(account, 'instagram', 7.days.ago)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
