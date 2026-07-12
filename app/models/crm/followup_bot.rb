# == Schema Information
#
# Table name: crm_followup_bots
#
#  id          :bigint           not null, primary key
#  active      :boolean          default(TRUE), not null
#  name        :string           not null
#  steps       :jsonb            not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  inbox_id    :bigint
#  pipeline_id :bigint
#  sender_id   :bigint
#  stage_id    :bigint
#
# Indexes
#
#  index_crm_followup_bots_on_account_id             (account_id)
#  index_crm_followup_bots_on_account_id_and_active  (account_id,active)
#  index_crm_followup_bots_on_inbox_id               (inbox_id)
#  index_crm_followup_bots_on_pipeline_id            (pipeline_id)
#  index_crm_followup_bots_on_sender_id              (sender_id)
#  index_crm_followup_bots_on_stage_id               (stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#  fk_rails_...  (sender_id => users.id)
#  fk_rails_...  (stage_id => crm_stages.id)
#
# Robô de follow-up: cadência de "cutucadas" simples para reabrir a conversa
# quando o paciente ficou em silêncio. Ex.: 3h "oi, pode falar?", 10h
# "[nome], no seu tempo ok?". Para automaticamente se o paciente responder.
class Crm::FollowupBot < ApplicationRecord
  self.table_name = 'crm_followup_bots'

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :pipeline, class_name: 'Crm::Pipeline', optional: true
  belongs_to :stage, class_name: 'Crm::Stage', optional: true
  belongs_to :sender, class_name: 'User', optional: true

  validates :name, presence: true
  validate :steps_must_be_valid
  validate :scope_must_be_present

  scope :active, -> { where(active: true) }

  # robô por coluna (modo programação) vs por caixa (global)
  def stage_scoped?
    stage_id.present?
  end

  # steps ordenados por atraso
  def ordered_steps
    Array(steps).sort_by { |s| s['delay_hours'].to_f }
  end

  private

  def scope_must_be_present
    return if inbox_id.present? || stage_id.present?

    errors.add(:base, 'Defina uma caixa de entrada ou uma coluna do CRM')
  end

  def steps_must_be_valid
    return errors.add(:steps, 'defina ao menos uma etapa') if Array(steps).blank?

    Array(steps).each do |s|
      errors.add(:steps, 'cada etapa precisa de tempo e mensagem') if s['message'].blank? || s['delay_hours'].blank?
    end
  end
end
