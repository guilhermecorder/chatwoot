# Plano de metas de UM mês (Painel de Metas): alvos por indicador,
# orientações, notas de ajuste por pessoa e marcos com check.
# == Schema Information
#
# Table name: cevico_goal_plans
#
#  id             :bigint           not null, primary key
#  guidance       :text
#  indicator_meta :jsonb            not null
#  milestones     :jsonb            not null
#  month          :date             not null
#  process_notes  :jsonb            not null
#  targets        :jsonb            not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_cevico_goal_plans_on_account_id            (account_id)
#  index_cevico_goal_plans_on_account_id_and_month  (account_id,month) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CevicoGoalPlan < ApplicationRecord
  belongs_to :account

  # indicadores oficiais do painel (histórico calculado mês a mês)
  INDICATORS = {
    'new_leads' => 'Novos leads',
    'appointments_booked' => 'Consultas agendadas',
    'consultations_attended' => 'Consultas realizadas',
    'surgeries_booked' => 'Cirurgias agendadas',
    'surgeries_done' => 'Cirurgias realizadas',
    'revenue_closed' => 'Valor fechado (R$)'
  }.freeze

  validates :month, presence: true, uniqueness: { scope: :account_id }
end
