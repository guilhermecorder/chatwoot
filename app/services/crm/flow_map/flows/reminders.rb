# 🔔 Confirmação de consulta (itens 156/250/253) — lembretes dN (0 a 7 dias
# antes) + confirmação por resposta — passos reais de
# app/jobs/crm/appointment_reminder_send_job.rb, crm_listener.rb (resposta
# "confirmo") e attendance_reminder_job.rb (conferência do dia) — item 170.
class Crm::FlowMap::Flows::Reminders
  FLOW = Crm::FlowMap::Flow.define(:reminders) do # rubocop:disable Metrics/BlockLength
    name 'Confirmação de consulta'
    group 'Atendimento ao paciente'
    icon 'i-lucide-bell-ring'
    color '#D97706'
    what 'manda a confirmação da consulta (quantos lembretes quiser: 2 dias antes, véspera, no dia) e registra quem confirmou'
    config tab: 'agentes', anchor: 'confirmacao'
    trigger :cron, 'A cada 15 min (só age na hora configurada)'
    jobs 'Crm::AppointmentReminderSendJob', 'Crm::AttendanceReminderJob'

    node :regua, 'Para cada lembrete (0 a 7 dias antes)', kind: :loop
    node :ligada, 'Régua ligada?', kind: :decision
    node :hora, 'É a hora configurada do lembrete?', kind: :decision
    node :caixa, 'Tem caixa e modelo?', kind: :decision
    node :alvo, 'Consultas do dia-alvo sem presença marcada'
    node :consulta, 'Para cada consulta', kind: :loop
    node :telefone, 'Contato tem telefone?', kind: :decision
    node :enviado, 'Já enviado para esta consulta?', kind: :decision
    node :pula, 'Pula esta consulta'
    node :envia, 'Envia o modelo pelo WhatsApp (hora, unidade)', kind: :external
    node :falhou, 'Falhou o envio?', kind: :decision
    node :marca, 'Marca a consulta como avisada'
    node :resposta, 'Paciente responde sim/confirmo'
    node :confirmado, 'Grava CONFIRMOU + nota ✅ na conversa', kind: :output
    node :conferencia, 'Conferência do dia (a cada 30 min)'
    node :limite, 'Dia útil, após o limite (19h) e pendentes > 0?', kind: :decision
    node :tarefa, 'Tarefa: concluir a conferência do dia', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :regua
    edge :regua, :ligada
    edge :ligada, :fim, 'não'
    edge :ligada, :hora, 'sim'
    edge :hora, :fim, 'não'
    edge :hora, :caixa, 'sim'
    edge :caixa, :fim, 'não'
    edge :caixa, :alvo, 'sim'
    edge :alvo, :consulta
    edge :consulta, :telefone
    edge :telefone, :pula, 'não'
    edge :telefone, :enviado, 'sim'
    edge :enviado, :pula, 'sim'
    edge :pula, :fim
    edge :enviado, :envia, 'não'
    edge :envia, :falhou
    edge :falhou, :fim, 'sim (não marca)'
    edge :falhou, :marca, 'não'
    edge :marca, :resposta
    edge :resposta, :confirmado
    edge :confirmado, :fim
    edge :trigger, :conferencia
    edge :conferencia, :limite
    edge :limite, :tarefa, 'sim'
    edge :tarefa, :fim
    edge :limite, :fim, 'não'

    live do |account|
      ag = agenda(account)
      rules = (ag['appointment_reminders'] || {}).select { |k, _| k.to_s.match?(/\Ad[0-7]\z/) }
      master = ag.dig('appointment_confirmation', 'enabled') != false
      on = rules.select { |_k, r| r['enabled'] == true }
      owners = (ag['attendance_owners'] || {}).values.compact_blank
      last = (ag['appointment_reminders_state'] || {}).values.filter_map { |st| st['last_run_at'] }.max
      {
        enabled: master && on.any?,
        last_run_at: last,
        counters: {
          'lembretes' => rules.size,
          'ligados' => master ? on.size : 0,
          'ao vivo' => master ? on.count { |_k, r| r['mode'] != 'shadow' } : 0,
          'responsáveis pela conferência' => owners.size
        },
        note: 'a marca de envio fica em cada consulta; a última rodada de cada lembrete aparece no card'
      }
    end
  end

  def self.flow
    FLOW
  end
end
