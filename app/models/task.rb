# == Schema Information
#
# Table name: tasks
#
#  id                  :bigint           not null, primary key
#  attendance          :string
#  canceled_at         :datetime
#  comments            :jsonb            not null
#  completed_at        :datetime
#  description         :text
#  doctor              :string
#  due_at              :datetime
#  indicated_procedure :string
#  modality            :string
#  phone               :string
#  priority            :integer          default("medium"), not null
#  procedure           :string
#  rescheduled_count   :integer          default(0), not null
#  status              :integer          default("todo"), not null
#  surgery_indication  :string
#  task_type           :string
#  title               :string           not null
#  unit                :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  assignee_id         :bigint
#  contact_id          :bigint
#  creator_id          :bigint           not null
#
# Indexes
#
#  index_tasks_on_account_id             (account_id)
#  index_tasks_on_account_id_and_status  (account_id,status)
#  index_tasks_on_account_id_and_unit    (account_id,unit)
#  index_tasks_on_assignee_id            (assignee_id)
#  index_tasks_on_contact_id             (contact_id)
#  index_tasks_on_creator_id             (creator_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (creator_id => users.id)
#
class Task < ApplicationRecord
  belongs_to :account
  belongs_to :creator, class_name: 'User'
  belongs_to :assignee, class_name: 'User', optional: true
  # Central do Paciente (Fase 0): consulta amarrada ao CONTATO de verdade;
  # o telefone vira fallback para paciente que ainda não existe no sistema.
  belongs_to :contact, optional: true

  validates :title, presence: true
  validate :contact_belongs_to_account

  enum status: { todo: 0, doing: 1, done: 2 }
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }

  before_save :link_contact_by_phone
  before_save :track_completion
  before_create :infer_consulta_modality

  # Tudo do paciente em um lugar só: casa por contact_id (unificado) e,
  # para registros antigos sem link, pelo telefone — sem repetir o regexp
  # frágil em cada dashboard.
  def self.for_patient(account, contact)
    digits = contact.phone_number.to_s.gsub(/\D/, '')
    scope = account.tasks
    return scope.where(contact_id: contact.id) if digits.length < 8

    scope.where(
      "contact_id = :cid OR (contact_id IS NULL AND regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE :tail)",
      cid: contact.id, tail: "%#{digits.last(8)}"
    )
  end

  # Contato da conta cujo telefone bate (últimos 8 dígitos) — critério
  # único do sistema para casar telefone com contato.
  def self.match_contact(account, phone)
    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.length < 8

    account.contacts
           .where("regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
           .order(:id).first
  end

  private

  # Toda task nasce (ou muda de telefone) já amarrada ao contato, venha de
  # onde vier: modal da Agenda, Secretário da Agenda, Atendente Instagram,
  # automações. Quem já informou o contato explicitamente vence.
  def link_contact_by_phone # rubocop:disable Metrics/CyclomaticComplexity
    return if phone.blank?
    return if contact_id.present? && (new_record? || will_save_change_to_contact_id?)
    return unless new_record? || will_save_change_to_phone?

    matched = Task.match_contact(account, phone)
    self.contact = matched if matched
  end

  def contact_belongs_to_account
    return if contact_id.blank? || contact.nil?
    return if contact.account_id == account_id

    errors.add(:contact, 'não pertence a esta conta')
  end

  def track_completion
    return unless status_changed?

    self.completed_at = done? ? Time.current : nil
  end

  # Tipo de consulta ACOMPANHA A JORNADA do paciente: consulta criada SEM
  # tipo explícito (Secretário da Agenda, Atendente Instagram, backfill)
  # nasce como RETORNO quando o paciente já tem consulta anterior (match por
  # telefone) e como AVALIAÇÃO quando é a primeira. Escolha manual no modal
  # sempre vence (o campo vem preenchido e o hook não mexe).
  def infer_consulta_modality # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return unless task_type == 'consulta' && modality.blank?

    had_before =
      if contact_id.present?
        # unificado: histórico do CONTATO (link_contact_by_phone roda antes)
        Task.for_patient(account, contact)
            .where(task_type: 'consulta')
            .exists?(['due_at < ?', due_at || Time.current])
      else
        digits = phone.to_s.gsub(/\D/, '')
        return self.modality = 'avaliacao' if digits.length < 8

        account.tasks
               .where(task_type: 'consulta')
               .where('due_at < ?', due_at || Time.current)
               .exists?(["regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}"])
      end
    self.modality = had_before ? 'retorno' : 'avaliacao'
  end
end
