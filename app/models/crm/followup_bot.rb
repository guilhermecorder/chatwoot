# == Schema Information
#
# Table name: crm_followup_bots
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  ends_at         :datetime
#  exclude_labels  :jsonb            not null
#  name            :string           not null
#  required_labels :jsonb            not null
#  starts_at       :datetime
#  steps           :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  inbox_id        :bigint
#  pipeline_id     :bigint
#  sender_id       :bigint
#  stage_id        :bigint
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

  scope :active, -> { where(active: true) }

  # robô por coluna (modo programação) vs por caixa (global)
  def stage_scoped?
    stage_id.present?
  end

  # Atraso da etapa em HORAS. Aceita o formato novo {delay_value, delay_unit}
  # (unit: 'minutes' | 'hours' | 'days') e o legado {delay_hours}.
  def self.step_delay_hours(step)
    return step['delay_hours'].to_f if step['delay_value'].blank?

    value = step['delay_value'].to_f
    case step['delay_unit']
    when 'days' then value * 24
    when 'minutes' then value / 60.0
    else value
    end
  end

  # steps ordenados por atraso
  def ordered_steps
    Array(steps).sort_by { |s| self.class.step_delay_hours(s) }
  end

  # janela de funcionamento: só age entre starts_at e ends_at (quando definidos)
  def within_window?(now = Time.current)
    return false if starts_at.present? && now < starts_at
    return false if ends_at.present? && now > ends_at

    true
  end

  private

  # caixa é OPCIONAL: sem caixa (modo automático) o follow-up sai pelo
  # número da própria conversa do card — cada paciente é cutucado pelo
  # mesmo número em que já conversa

  def steps_must_be_valid
    return errors.add(:steps, 'defina ao menos uma etapa') if Array(steps).blank?

    Array(steps).each do |s|
      delay_missing = s['delay_hours'].blank? && s['delay_value'].blank?
      content_missing = s['message'].blank? && s['template_params'].blank?
      errors.add(:steps, 'cada etapa precisa de tempo e mensagem (texto ou modelo)') if delay_missing || content_missing
    end
  end
end
