# Anotação clínica da consulta (Espaço Nobre do Médico — Central do
# Paciente, Fase 2). ⚠️ LGPD: dado de saúde é SENSÍVEL — isto é anotação
# INTERNA da clínica (não substitui prontuário certificado SBIS/CFM);
# quem pode ver/editar é decidido no controller (médicos e admin).
#
# fields (campos rápidos, jsonb):
#   procedure_type  refrativa | catarata | outro
#   technique       PRK | Lasik (refrativa)
#   lens_type       nacional | Rayner | foco estendido | trifocal | tórica... (catarata)
#   eye             OD | OE | AO
#   refraction_od / refraction_oe, acuity_od / acuity_oe, pio_od / pio_oe
#   biomicroscopy, fundoscopy
#   conduct         [pílulas de conduta/indicação]
#   exams_requested [exames pedidos]
#   surgery_indicated  true quando o médico saiu indicando cirurgia
# == Schema Information
#
# Table name: crm_clinical_notes
#
#  id           :bigint           not null, primary key
#  doctor       :string
#  fields       :jsonb            not null
#  observations :text
#  performed_at :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  author_id    :bigint           not null
#  contact_id   :bigint           not null
#  task_id      :bigint
#
# Indexes
#
#  index_clinical_notes_on_account_contact_performed  (account_id,contact_id,performed_at)
#  index_crm_clinical_notes_on_account_id             (account_id)
#  index_crm_clinical_notes_on_author_id              (author_id)
#  index_crm_clinical_notes_on_contact_id             (contact_id)
#  index_crm_clinical_notes_on_task_id                (task_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (author_id => users.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (task_id => tasks.id)
#
class Crm::ClinicalNote < ApplicationRecord
  self.table_name = 'crm_clinical_notes'

  belongs_to :account
  belongs_to :contact, class_name: '::Contact'
  belongs_to :task, optional: true
  belongs_to :author, class_name: 'User'

  has_many_attached :photos # fotos de exames (storage entra no plano de backup!)

  validates :performed_at, presence: true
  validate :contact_belongs_to_account

  scope :for_patient, ->(contact_id) { where(contact_id: contact_id).order(performed_at: :desc) }

  private

  def contact_belongs_to_account
    return if contact.nil? || contact.account_id == account_id

    errors.add(:contact, 'não pertence a esta conta')
  end
end
