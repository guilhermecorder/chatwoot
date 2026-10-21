# 🔔 ITEM 346 — etapa 3: os botões das NOTIFICAÇÕES SOBRE AGENDAMENTOS.
# Tudo aqui é decisão de uma PESSOA (a conferência é manual, pedido dele):
#   merge!       "Juntar" — fica o cadastro escolhido; o outro entra nele
#                (consultas, card, conversas — Cevico::ContactMergeRecords).
#                Se o que sai veio do OftalmoFácil, nome/e-mail/CPF dele mandam.
#   not_same!    "São pessoas diferentes" — some e não volta a alertar.
#   move_task!   "Mover a consulta" — para outro cadastro ou para um paciente
#                novo (nome + telefone); quem estava com ela vira "agendou para".
#   rename!      "Corrigir o nome" (ex.: "Francislene … E Alice …").
#   reviewed!    "Conferido" — tira o alerta sem mudar nada.
class Crm::AppointmentAlertActions
  def initialize(account:, user: nil)
    @account = account
    @user = user
  end

  def merge!(keep_id:, drop_id:) # rubocop:disable Metrics/AbcSize
    keep = contact(keep_id)
    drop = contact(drop_id)
    raise ArgumentError, 'escolha dois cadastros diferentes' if keep.id == drop.id

    of_data = of_origin?(drop) ? { name: drop.name, email: drop.email, cpf: drop.custom_attributes.to_h['cpf'] } : nil
    labels = drop.label_list
    Contact.without_label_triggers do
      ContactMergeAction.new(account: @account, base_contact: keep, mergee_contact: drop).perform
      keep.reload.add_labels(labels)
    end
    apply_of_data!(keep.reload, of_data) if of_data
    Crm::PatientReview.clear!(keep.reload, 'possivel_duplicado', other_id: drop.id)
    Crm::PatientReview.clear!(keep.reload, 'nome_diferente', other_id: drop.id)
    keep.reload
  end

  def not_same!(one_id:, other_id:)
    Crm::PatientReview.not_same!(contact(one_id), contact(other_id))
  end

  # consulta para outro cadastro (contact_id) ou para um paciente novo (name + phone)
  def move_task!(task_id:, contact_id: nil, name: nil, phone: nil)
    task = @account.tasks.find(task_id)
    previous = task.contact
    patient = if contact_id.present?
                contact(contact_id)
              else
                raise ArgumentError, 'informe o nome do paciente' if name.blank?

                Crm::PatientLink.patient_for!(account: @account, requester: previous, name: name, phone: phone)
              end
    raise ArgumentError, 'a consulta já está nesse cadastro' if previous&.id == patient.id

    task.update!(contact: patient, phone: patient.phone_number.presence || task.phone)
    ensure_card!(patient, previous)
    Crm::PatientLink.link!(requester: previous, patient: patient) if previous
    Crm::AppointmentAlerts.mark_task_reviewed!(@account, task.id)
    task
  end

  def rename!(contact_id:, name:)
    person = contact(contact_id)
    raise ArgumentError, 'nome vazio' if name.to_s.strip.blank?

    person.update!(name: name.to_s.strip)
    Crm::PatientReview.clear!(person.reload, 'duas_pessoas')
    person
  end

  def reviewed!(contact_id: nil, type: nil, other_id: nil, task_id: nil)
    return Crm::AppointmentAlerts.mark_task_reviewed!(@account, task_id) if task_id.present?

    Crm::PatientReview.clear!(contact(contact_id), type, other_id: other_id.presence&.to_i)
  end

  private

  def contact(id)
    @account.contacts.find(id)
  end

  def of_origin?(person)
    person.additional_attributes.to_h['origem'] == 'oftalmofacil'
  end

  def apply_of_data!(keep, data)
    changes = {}
    changes[:name] = data[:name] if data[:name].present?
    changes[:email] = data[:email] if data[:email].present? && !@account.contacts.where.not(id: keep.id).exists?(email: data[:email])
    changes[:custom_attributes] = keep.custom_attributes.to_h.merge('cpf' => data[:cpf]) if data[:cpf].present?
    keep.update_columns(changes) if changes.any? # rubocop:disable Rails/SkipsModelValidations
  end

  # o paciente que recebeu a consulta precisa de card: nasce na coluna do card
  # de quem estava com ela (ou na de agendamento), SEM disparar automação
  # (a consulta já existia — não é agendamento novo nem mensagem nova)
  def ensure_card!(patient, previous)
    return if Crm::Contact.exists?(contact_id: patient.id)

    source = previous && Crm::Contact.where(contact_id: previous.id).order(stage_moved_at: :desc).first
    stage_id = source&.stage_id || Crm::BookingSideEffects.booking_stage_id(@account)
    stage = stage_id && Crm::Stage.find_by(id: stage_id)
    return unless stage

    Crm::Contact.create!(contact_id: patient.id, pipeline_id: stage.pipeline_id, stage_id: stage.id, assignee_id: source&.assignee_id)
  end
end
