# Feedback semanal do Mentor do Time para um usuário: os números da semana
# (stats) e a leitura da IA (feedback: resumo, ponto forte, ponto fraco e
# soluções simples). Um registro por usuário por semana.
# == Schema Information
#
# Table name: crm_weekly_feedbacks
#
#  id         :bigint           not null, primary key
#  cadence    :string           default("weekly"), not null
#  feedback   :jsonb            not null
#  stats      :jsonb            not null
#  week_start :date             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  idx_crm_weekly_feedbacks_unique           (account_id,user_id,week_start,cadence) UNIQUE
#  index_crm_weekly_feedbacks_on_account_id  (account_id)
#  index_crm_weekly_feedbacks_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class Crm::WeeklyFeedback < ApplicationRecord
  self.table_name = 'crm_weekly_feedbacks'

  belongs_to :account
  belongs_to :user

  CADENCES = %w[weekly monthly].freeze

  validates :cadence, inclusion: { in: CADENCES }
  validates :week_start, presence: true, uniqueness: { scope: [:account_id, :user_id, :cadence] }
end
