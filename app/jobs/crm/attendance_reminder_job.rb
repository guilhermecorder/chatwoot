# Prazo da CONFERÊNCIA DO DIA: se o horário limite passou e ainda há
# consultas/cirurgias do dia sem Compareceu/Faltou marcados, cria a tarefa
# "Concluir a conferência do dia" para a responsável configurada
# (agenda_config.attendance_owners — uma pessoa para consultas, outra
# para cirurgias). A tarefa acende o badge dourado da sidebar e o aviso
# "esperando você" no Meu Painel dela. Cron a cada 30 min; cria no máximo
# 1 tarefa por tipo por dia.
class Crm::AttendanceReminderJob < ApplicationJob
  queue_as :scheduled_jobs

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  DEFAULT_DEADLINE = '19:00'.freeze

  def perform
    CrmSetting.find_each do |settings|
      owners = settings.agenda_config&.dig('attendance_owners') || {}
      next if owners['consulta_user_id'].blank? && owners['cirurgia_user_id'].blank?

      check_account(settings.account, owners)
    rescue StandardError => e
      Rails.logger.error "[CEVICO conferência] conta #{settings.account_id}: #{e.message}"
    end
  end

  private

  def check_account(account, owners)
    now = TZ.now
    return if now.on_weekend?

    deadline = parse_deadline(owners['deadline'], now)
    return if now < deadline

    remind(account, owners['consulta_user_id'], 'consulta', Segmento.frase('conferencia_atendimentos', 'Consultas'), now)
    remind(account, owners['cirurgia_user_id'], 'cirurgia', Segmento.frase('conferencia_vendas', 'Cirurgias'), now)
  end

  def parse_deadline(value, now)
    hh, mm = (value.presence || DEFAULT_DEADLINE).split(':').map(&:to_i)
    now.change(hour: hh, min: mm)
  rescue StandardError
    now.change(hour: 19, min: 0)
  end

  def remind(account, user_id, task_type, label, now)
    return if user_id.blank?

    owner = account.users.find_by(id: user_id)
    return if owner.blank?

    # pendentes = agendamentos de HOJE que já passaram e ninguém conferiu
    pending = account.tasks
                     .where(task_type: task_type, canceled_at: nil, attendance: nil)
                     .where(due_at: now.beginning_of_day..now)
                     .count
    return if pending.zero?

    title = "✅ Concluir a conferência do dia — #{label} (#{now.strftime('%d/%m')})"
    return if account.tasks.where(title: title).where(created_at: now.all_day).exists?

    creator = account.administrators.first || owner
    account.tasks.create!(
      title: title,
      description: "#{pending} agendamento(s) de hoje ainda sem ✓ Compareceu / ✗ Faltou. " \
                   'Abra a Agenda → visão Dia e conclua a conferência.',
      task_type: 'Atendimento',
      priority: :high,
      status: :todo,
      due_at: now.end_of_day,
      creator: creator,
      assignee: owner
    )
    Rails.logger.info "[CEVICO conferência] tarefa criada p/ #{owner.name} (#{label}, #{pending} pendentes)"
  end
end
