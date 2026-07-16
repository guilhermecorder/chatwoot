# Registra na Agenda o resultado do Agente de Agendamento:
# - cria a consulta nova, OU
# - REAGENDA a consulta futura já existente do mesmo paciente (telefone/nome)
#   em vez de duplicar — cobre "preciso remarcar" sem criar consulta fantasma.
# Usado pela ação de coluna "Agendar consulta (IA)" e pelo preenchimento do
# histórico (Crm::AgendaBackfillJob). NÃO fala com o paciente: só escreve na
# Agenda interna.
class Crm::AppointmentRecorder
  def self.record(account:, result:, contact: nil, conversation: nil, default_unit: nil)
    outcome = do_record(account: account, result: result, contact: contact,
                        conversation: conversation, default_unit: default_unit)
    stamp_gender(contact, result[:gender])
    log_activity(account, result, contact, conversation, outcome)
    outcome
  end

  # sexo do paciente detectado na conversa (nome/contexto) → anotado no
  # contato; o Espaço do Paciente muda de cor sozinho. Marcação manual da
  # equipe vence: só grava se ainda não tem.
  def self.stamp_gender(contact, gender)
    return if contact.blank? || gender.blank?

    attrs = contact.additional_attributes || {}
    return if attrs['sexo'].present?

    contact.update!(additional_attributes: attrs.merge('sexo' => gender))
  rescue StandardError => e
    Rails.logger.warn "[Crm::AppointmentRecorder] sexo: #{e.message}"
  end

  def self.do_record(account:, result:, contact: nil, conversation: nil, default_unit: nil)
    return :skipped unless result[:found] && result[:starts_at].present?

    name  = result[:name].presence || contact&.name.presence || 'Paciente'
    phone = result[:phone].presence || contact&.phone_number
    unit  = result[:unit].presence || default_unit
    creator = account.administrators.first || account.users.first
    return :skipped unless creator

    notes = [
      result[:price].presence && "Valor da consulta: #{result[:price]}",
      result[:notes].presence,
      conversation && "Conversa ##{conversation.display_id} — agendado pela IA"
    ].compact.join("\n")

    # mesmo paciente + mesmo horário = já está na Agenda
    return :already if account.tasks.exists?(due_at: result[:starts_at], title: "Consulta: #{name}")

    # REAGENDAMENTO: se o paciente já tem consulta FUTURA, ela vira o novo horário
    future = future_appointment(account, phone, name, contact)
    if future
      return :already if future.due_at == result[:starts_at]

      future.rescheduled_count += 1
      future.update!(
        due_at: result[:starts_at],
        unit: unit.presence || future.unit,
        doctor: result[:doctor].presence || future.doctor,
        procedure: result[:procedure].presence || future.procedure,
        phone: phone.presence || future.phone,
        contact: contact || future.contact,
        description: [future.description.presence, "Reagendada pela IA:\n#{notes}"].compact.join("\n\n"),
        canceled_at: nil,
        status: :todo
      )
      return :rescheduled
    end

    account.tasks.create!(
      title: "Consulta: #{name}",
      description: notes,
      due_at: result[:starts_at],
      unit: unit,
      phone: phone,
      contact: contact,
      procedure: result[:procedure].presence,
      doctor: result[:doctor].presence,
      task_type: 'consulta',
      priority: :medium,
      status: :todo,
      creator: creator
    )
    :created
  end

  # Registro de atividade do Secretário (visível no card do agente):
  # cada leitura vira uma linha — criada/reagendada/já existia/sem dados —
  # para a equipe ENTENDER os números e conferir o funcionamento.
  def self.log_activity(account, result, contact, conversation, outcome)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    cfg = settings.agenda_config || {}
    log = Array(cfg['scheduler_log'])
    log.unshift({
                  'at' => Time.current.iso8601,
                  'name' => (result[:name].presence || contact&.name || 'Paciente').to_s.first(60),
                  'when' => result[:starts_at]&.iso8601,
                  'outcome' => outcome.to_s,
                  'conversation_id' => conversation&.display_id
                })
    cfg['scheduler_log'] = log.first(100)
    settings.update!(agenda_config: cfg)
  rescue StandardError => e
    Rails.logger.warn "[Crm::AppointmentRecorder] log: #{e.message}"
  end

  # consulta futura ativa do mesmo CONTATO (unificado), telefone (últimos
  # 8 dígitos) ou nome — nessa ordem de confiança
  def self.future_appointment(account, phone, name, contact = nil)
    scope = account.tasks.where(task_type: 'consulta', canceled_at: nil)
                   .where('due_at > ?', Time.current)
                   .where.not(status: 'done')

    if contact
      by_contact = scope.where(contact_id: contact.id).order(:due_at).first
      return by_contact if by_contact
    end

    digits = phone.to_s.gsub(/\D/, '')
    if digits.length >= 8
      by_phone = scope.where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
                      .order(:due_at).first
      return by_phone if by_phone
    end

    scope.find_by(title: "Consulta: #{name}")
  end
end
