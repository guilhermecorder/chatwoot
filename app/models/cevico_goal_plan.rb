# Plano de metas de UM período (Painel de Metas): alvos por indicador,
# orientações, notas de ajuste por pessoa e marcos com check. `month` guarda
# o INÍCIO do período (dia 1 do mês, segunda da semana, sábado do fim de
# semana…) e `period_type` diz qual ambiente de meta é.
# == Schema Information
#
# Table name: cevico_goal_plans
#
#  id             :bigint           not null, primary key
#  guidance       :text
#  indicator_meta :jsonb            not null
#  milestones     :jsonb            not null
#  month          :date             not null
#  period_type    :string           default("month"), not null
#  process_notes  :jsonb            not null
#  targets        :jsonb            not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_cevico_goal_plans_on_account_id            (account_id)
#  index_cevico_goal_plans_on_account_period_start  (account_id,period_type,month) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CevicoGoalPlan < ApplicationRecord
  belongs_to :account

  # indicadores oficiais do painel (histórico calculado período a período)
  INDICATORS = {
    'new_leads' => 'Novos leads',
    'appointments_booked' => 'Consultas agendadas',
    'consultations_attended' => 'Consultas realizadas',
    'surgeries_booked' => 'Cirurgias agendadas',
    'surgeries_done' => 'Cirurgias realizadas',
    'revenue_closed' => 'Valor fechado (R$)'
  }.freeze

  # metas de INDICADORES (%): derivadas dos números acima, meta em percentual
  RATE_INDICATORS = {
    'rate_scheduling' => '% de agendamento (lead → consulta)',
    'rate_attendance' => '% de comparecimento (agendada → realizada)',
    'rate_surgery' => '% de conversão (consulta → cirurgia)'
  }.freeze

  ALL_INDICATORS = INDICATORS.merge(RATE_INDICATORS).freeze

  # ambientes de meta (item 58): 'month' é o oficial dos selos/dashboards
  PERIOD_TYPES = %w[day week weekend month quarter year].freeze

  validates :month, presence: true, uniqueness: { scope: [:account_id, :period_type] }
  validates :period_type, inclusion: { in: PERIOD_TYPES }
end
