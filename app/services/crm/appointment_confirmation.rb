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
module Crm::AppointmentConfirmation
  DECLINE_LABEL = 'confirmar_urgente'.freeze

  module_function

  # devolve o nome da coluna para onde o card andou (ou nil)
  def confirm!(account:, task:, contact:)
    mark_reminder!(contact, task, 'confirmed')
    task.update!(confirmed_at: Time.current, declined_at: nil)
    Crm::ConfirmationReflector.call(account: account, task: task)
  end

  def decline!(account:, task:, contact:, conversation: nil, agent_key: 'lembrete')
    mark_reminder!(contact, task, 'declined')
    task.update!(declined_at: Time.current)
    ensure_label!(account)
    [contact, conversation].compact.each do |target|
      target.add_labels([DECLINE_LABEL]) if target.label_list.exclude?(DECLINE_LABEL)
    end
    Crm::AgentAlert.push(account: account, kind: 'nao_confirmou', task: task, conversation: conversation, agent_key: agent_key) if conversation
    true
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
