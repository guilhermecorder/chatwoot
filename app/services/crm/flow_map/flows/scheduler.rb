# 📅 Secretário da Agenda — passos reais de app/services/crm/appointment_applier.rb,
# appointment_extraction_service.rb e appointment_recorder.rb (item 170).
class Crm::FlowMap::Flows::Scheduler
  FLOW = Crm::FlowMap::Flow.define(:scheduler) do # rubocop:disable Metrics/BlockLength
    name 'Secretário da Agenda'
    group 'Atendimento ao paciente'
    icon 'i-lucide-calendar-check'
    color '#0F5FA6'
    what 'lê confirmações de agendamento e anota as consultas na Agenda'
    config tab: 'agentes', anchor: 'scheduler'
    trigger :event, 'Ação de coluna ou releitura 20 s após a mensagem'
    jobs 'Crm::SchedulerRecheckJob'

    node :ligado, 'Agente ligado?', kind: :decision
    node :conversa, 'Tem conversa e contato?', kind: :decision
    node :releitura, 'Releitura do mesmo contato há < 2 min?', kind: :decision
    node :carimba, 'Carimba a última leitura no contato'
    node :ia, 'IA extrai nome, data, hora, unidade, médico', kind: :ai
    node :chave, 'Sem chave ou agente pausado?', kind: :decision
    node :erro, 'Linha de erro no registro da Agenda', kind: :output
    node :cancel, 'Pediu cancelar sem novo horário?', kind: :decision
    node :cancela, 'Cancela a consulta futura'
    node :tinha_futura, 'Tinha consulta futura?', kind: :decision
    node :tarefa_cancel, 'Tarefa: pediu cancelar/remarcar', kind: :output
    node :achou, 'Achou dia e hora?', kind: :decision
    node :existe, 'Consulta já existe?', kind: :decision
    node :ja, 'Já estava anotada'
    node :futura, 'Consulta futura do mesmo contato?', kind: :decision
    node :reagenda, 'Reagenda a consulta'
    node :cria, 'Cria a consulta na Agenda'
    node :nota, 'Nota privada: agendada/reagendada pela IA', kind: :output
    node :tarefa_conf, 'Tarefa: confirmar consulta', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :conversa, 'sim'
    edge :conversa, :fim, 'não'
    edge :conversa, :releitura, 'sim'
    edge :releitura, :fim, 'sim'
    edge :releitura, :carimba, 'não'
    edge :carimba, :ia
    edge :ia, :chave
    edge :chave, :erro, 'sim'
    edge :erro, :fim
    edge :chave, :cancel, 'não'
    edge :cancel, :cancela, 'sim'
    edge :cancela, :tinha_futura
    edge :tinha_futura, :nota, 'sim'
    edge :tinha_futura, :tarefa_cancel, 'não'
    edge :tarefa_cancel, :fim
    edge :cancel, :achou, 'não'
    edge :achou, :tarefa_conf, 'não'
    edge :tarefa_conf, :fim
    edge :achou, :existe, 'sim'
    edge :existe, :ja, 'sim'
    edge :ja, :fim
    edge :existe, :futura, 'não'
    edge :futura, :reagenda, 'sim'
    edge :futura, :cria, 'não'
    edge :reagenda, :nota
    edge :cria, :nota
    edge :nota, :fim

    live do |account|
      log = Array(agenda(account)['scheduler_log'])
      {
        enabled: agent_enabled?(account, 'scheduler'),
        last_run_at: last_at(log) || usage_last(account, 'scheduler'),
        counters: {
          'leituras hoje' => count_today(log),
          'leituras no registro' => log.size,
          'chamadas de IA (7 dias)' => usage_count(account, 'scheduler', 7.days.ago)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
