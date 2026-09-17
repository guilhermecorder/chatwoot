# 🔔 Lembretes D-1/D-0 + confirmação (item 156) — passos reais de
# app/jobs/crm/appointment_reminder_send_job.rb, crm_listener.rb (resposta
# "confirmo") e attendance_reminder_job.rb (conferência do dia) — item 170.
class Crm::FlowMap::Flows::Reminders
  FLOW = Crm::FlowMap::Flow.define(:reminders) do # rubocop:disable Metrics/BlockLength
    name 'Lembretes da consulta'
    group 'Atendimento ao paciente'
    icon 'i-lucide-bell-ring'
    color '#D97706'
    what 'manda o lembrete da véspera e do dia da consulta e registra quem confirmou'
    config tab: 'robos', anchor: 'lembretes'
    trigger :cron, 'A cada 15 min (só age na hora configurada)'
    jobs 'Crm::AppointmentReminderSendJob', 'Crm::AttendanceReminderJob'

    node :regua, 'Para cada régua: D-1 (véspera) e D-0 (no dia)', kind: :loop
    node :ligada, 'Régua ligada?', kind: :decision
    node :hora, 'É a hora configurada (D-1 10h, D-0 7h)?', kind: :decision
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
      cfg = agenda(account)['appointment_reminders'] || {}
      d1 = cfg['d1'] || {}
      d0 = cfg['d0'] || {}
      owners = (agenda(account)['attendance_owners'] || {}).values.compact_blank
      {
        enabled: d1['enabled'] == true || d0['enabled'] == true,
        last_run_at: nil,
        counters: {
          'D-1 (véspera)' => d1['enabled'] == true ? "ligado às #{d1['hour'].presence || '10:00'}" : 'desligado',
          'D-0 (no dia)' => d0['enabled'] == true ? "ligado às #{d0['hour'].presence || '07:00'}" : 'desligado',
          'responsáveis pela conferência' => owners.size
        },
        note: 'a marca de envio fica em cada consulta (sem histórico geral)'
      }
    end
  end

  def self.flow
    FLOW
  end
end
