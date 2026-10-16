# 🔔 ITEM 346 — etapa 3 (16/10): NOTIFICAÇÕES SOBRE AGENDAMENTOS. Pedido do
# Guilherme: "criar um ambiente de notificações sobre agendamentos, e colocar
# lá todos os agendamentos com divergência de dados, para conferência e ajuste
# manual" — "alerta para os ADMIN e para os agentes responsáveis".
#
# O que entra (nada é corrigido sozinho):
#   cadastro     possível duplicado · nome diferente no mesmo celular · CPF
#                diferente · duas pessoas no mesmo cadastro (Crm::PatientReview)
#   consulta     marcada no cadastro de OUTRA pessoa (o nome da consulta não é
#                o do cadastro — caso "Consulta: Alice" na ficha da Francislene)
#                · consulta sem cadastro (ninguém ligado a ela)
# Admin vê tudo; o atendente vê o que é dele (responsável pelo card ou pela consulta).
class Crm::AppointmentAlerts
  WINDOW_PAST = 7.days
  WINDOW_FUTURE = 120.days
  REVIEWED_KEY = 'agendamentos_conferidos'.freeze
  MAX_REVIEWED = 3000
  PATIENT_TYPES = %w[consulta cirurgia].freeze

  def initialize(account:, user: nil, admin: true)
    @account = account
    @user = user
    @admin = admin
  end

  def items
    list = contact_items + other_name_items + no_contact_items
    list = list.select { |item| mine?(item) } unless @admin
    list.sort_by { |item| item[:when] || item[:at] || '' }
  end

  def count
    items.size
  end

  # ── conferido sem mudar nada (consulta) ────────────────────────────────
  def self.mark_task_reviewed!(account, task_id)
    Cevico::SettingMerge.merge!(account, :agenda_config) do |cfg|
      cfg[REVIEWED_KEY] = (Array(cfg[REVIEWED_KEY]) | [task_id.to_i]).last(MAX_REVIEWED)
      cfg
    end
  end

  private

  def reviewed_task_ids
    @reviewed_task_ids ||= Array(CrmSetting.find_by(account_id: @account.id)&.agenda_config&.dig(REVIEWED_KEY)).to_set(&:to_i)
  end

  # cadastros com alerta (o par A↔B aparece uma vez só)
  def contact_items
    seen = Set.new
    flagged_contacts.flat_map do |contact|
      Crm::PatientReview.list(contact).filter_map do |flag|
        pair = [flag['tipo'], [contact.id, flag['outro_contact_id']].compact.sort]
        next if seen.include?(pair)

        seen << pair
        other = flag['outro_contact_id'] && others[flag['outro_contact_id']]
        next if flag['outro_contact_id'] && other.nil? # o outro já foi juntado/apagado

        contact_item(contact, other, flag)
      end
    end
  end

  def flagged_contacts
    @flagged_contacts ||= @account.contacts.where("additional_attributes -> 'cevico_conferir' IS NOT NULL").limit(1000).to_a
  end

  def others
    @others ||= begin
      ids = flagged_contacts.flat_map { |c| Crm::PatientReview.list(c).filter_map { |f| f['outro_contact_id'] } }.uniq
      @account.contacts.where(id: ids).index_by(&:id)
    end
  end

  def contact_item(contact, other, flag)
    {
      key: "c#{contact.id}-#{flag['tipo']}-#{other&.id}", kind: flag['tipo'], group: 'cadastro',
      title: flag['titulo'], detail: flag['detalhe'], at: flag['at'],
      contact: person(contact), other: other && person(other),
      next_appointment: next_task(contact.id) || (other && next_task(other.id))
    }
  end

  # consulta no cadastro de OUTRA pessoa
  def other_name_items
    upcoming.where.not(contact_id: nil).includes(:contact).filter_map do |task|
      name = Crm::AppointmentRecorder.patient_title(task)
      contact = task.contact
      next if contact.nil? || Crm::AppointmentRecorder.placeholder_name?(name) || Crm::AppointmentRecorder.placeholder_name?(contact.name)
      # apelido do WhatsApp ("Fran") × nome da consulta ("Francislene …") não é alerta
      next if Crm::PatientReview.compatible_names?(name, contact.name)

      task_item(task, 'consulta_outro_nome', 'Consulta com o nome de outra pessoa',
                "A consulta é de \"#{name}\", mas está no cadastro de #{contact.name}")
    end
  end

  def no_contact_items
    upcoming.where(contact_id: nil).map do |task|
      phone = task.phone.present? ? " (#{task.phone})" : ' e não tem telefone'
      task_item(task, 'consulta_sem_cadastro', 'Consulta sem cadastro',
                "#{Crm::AppointmentRecorder.patient_title(task)} não está ligado a nenhum paciente#{phone}")
    end
  end

  def upcoming
    now = Time.current
    @account.tasks.where(canceled_at: nil, task_type: PATIENT_TYPES)
            .where(due_at: (now - WINDOW_PAST)..(now + WINDOW_FUTURE))
            .where.not(id: reviewed_task_ids.to_a)
            .order(:due_at).limit(500)
  end

  def task_item(task, kind, title, detail)
    {
      key: "t#{task.id}-#{kind}", kind: kind, group: 'consulta', title: title, detail: detail,
      when: task.due_at&.iso8601, contact: task.contact && person(task.contact),
      task: { id: task.id, title: task.title, patient: Crm::AppointmentRecorder.patient_title(task), due_at: task.due_at&.iso8601,
              unit: task.unit, phone: task.phone, type: task.task_type, assignee_id: task.assignee_id }
    }
  end

  def person(contact)
    card = cards[contact.id]
    { id: contact.id, name: contact.name, phone_number: contact.phone_number, email: contact.email,
      origin: contact.additional_attributes.to_h['origem'], stage: card&.stage&.name, assignee_id: card&.assignee_id,
      conversations: conversation_counts[contact.id].to_i }
  end

  # só dos pacientes envolvidos nos alertas (não da conta inteira)
  def involved_ids
    @involved_ids ||= (flagged_contacts.map(&:id) + others.keys + upcoming.where.not(contact_id: nil).pluck(:contact_id)).uniq
  end

  def cards
    @cards ||= Crm::Contact.where(contact_id: involved_ids).includes(:stage).order(:stage_moved_at).index_by(&:contact_id)
  end

  def conversation_counts
    @conversation_counts ||= @account.conversations.where(contact_id: involved_ids).group(:contact_id).count
  end

  def next_task(contact_id)
    task = @account.tasks.where(contact_id: contact_id, canceled_at: nil).where('due_at >= ?', Time.current).order(:due_at).first
    task && { id: task.id, title: task.title, due_at: task.due_at.iso8601 }
  end

  # do atendente: responsável pelo card de alguém do alerta ou pela consulta
  def mine?(item)
    ids = [item.dig(:contact, :assignee_id), item.dig(:other, :assignee_id), item.dig(:task, :assignee_id)]
    ids.compact.include?(@user&.id)
  end
end
