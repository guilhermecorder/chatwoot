# ✅/❌ RESPOSTA DO PACIENTE À CONSULTA MARCADA (item 333, 08/10 — extraído do
# CrmListener para a ligação usar o MESMO caminho do WhatsApp). Venha do
# SIM/NÃO ao lembrete ou da conversa com a assistente virtual por telefone:
#   · grava na consulta (selo da Agenda, painel Agendamentos, indicadores);
#   · marca o lembrete como respondido (o reforço não sai mais);
#   · confirmou → o card anda para "Consulta Confirmada" (Crm::ConfirmationReflector,
#     no funil do Oftalmofácil quando o paciente é de lá);
#   · não vai   → etiqueta confirmar_urgente no paciente e na conversa + aviso
#     no Meu Painel ("ligar para remarcar ou cancelar"). A consulta continua na
#     Agenda: quem cancela é a equipe.
#
# 🔁 Auditoria 10/2026 (#462/#472): a mesma consulta pode existir duas vezes
# no mesmo dia (lançada pela recepção E vinda do hub, antes de o sync unir).
# O sim/não do paciente vale para TODAS as consultas ativas dele no mesmo dia
# (São Paulo) que ainda estão pendentes — venha pelo WhatsApp, pela assistente
# de ligação ou pelo botão "confirmou" da equipe. Senão a outra continua "não
# confirmada" e recebe D-1/D-0/reforço de novo. (Isso também confirma duas
# consultas de verdade diferentes no mesmo dia, ex.: avaliação 09:00 + exame
# 14:00 — o paciente confirma o dia. Decisão registrada para o Guilherme.)
module Crm::AppointmentConfirmation
  DECLINE_LABEL = 'confirmar_urgente'.freeze
  TZ = 'America/Sao_Paulo'.freeze

  module_function

  # devolve o nome da coluna para onde o card andou (ou nil)
  def confirm!(account:, task:, contact:)
    mark_reminder!(contact, task, 'confirmed')
    task.update!(confirmed_at: Time.current, declined_at: nil)
    confirm_twins!(task, contact)
    Crm::ConfirmationReflector.call(account: account, task: task)
  end

  def decline!(account:, task:, contact:, conversation: nil, agent_key: 'lembrete')
    mark_reminder!(contact, task, 'declined')
    task.update!(declined_at: Time.current)
    decline_twins!(task, contact)
    ensure_label!(account)
    [contact, conversation].compact.each do |target|
      target.add_labels([DECLINE_LABEL]) if target.label_list.exclude?(DECLINE_LABEL)
    end
    Crm::AgentAlert.push(account: account, kind: 'nao_confirmou', task: task, conversation: conversation, agent_key: agent_key) if conversation
    true
  end

  # as outras consultas ATIVAS do mesmo paciente no mesmo dia que ainda não
  # têm a resposta (`pending` = :confirmed_at ou :declined_at)
  def same_day_pending(task, pending)
    return Task.none if task.contact_id.blank? || task.due_at.blank? || task.task_type != 'consulta'

    day = task.due_at.in_time_zone(TZ)
    task.account.tasks
        .where(task_type: 'consulta', contact_id: task.contact_id, canceled_at: nil, archived_at: nil)
        .where(attendance: [nil, ''], due_at: day.all_day)
        .where(pending => nil)
        .where.not(id: task.id)
        .order(:due_at)
  end

  # só a marca e a data: o card já andou (e o aviso já saiu) pela consulta principal
  def confirm_twins!(task, contact)
    same_day_pending(task, :confirmed_at).each do |other|
      mark_reminder!(contact, other, 'confirmed')
      other.update!(confirmed_at: Time.current, declined_at: nil)
    end
  end

  def decline_twins!(task, contact)
    same_day_pending(task, :declined_at).each do |other|
      mark_reminder!(contact, other, 'declined')
      other.update!(declined_at: Time.current)
    end
  end

  def mark_reminder!(contact, task, key)
    return if contact.blank?

    Cevico::AttributeMerge.merge!(contact) do |attrs|
      all = attrs['cevico_appt_reminders'] || {}
      (all[task.id.to_s] ||= {})[key] = Time.current.iso8601
      attrs.merge('cevico_appt_reminders' => all)
    end
  end

  def ensure_label!(account)
    return if account.labels.exists?(title: DECLINE_LABEL)

    account.labels.create!(title: DECLINE_LABEL, color: '#DC2626', show_on_sidebar: true)
  end
end
