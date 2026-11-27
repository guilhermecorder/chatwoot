# Um dia de uso do sistema por pessoa (27/11/2026, LIFE): 1º e último acesso. Gravado pelo Crm::PresenceTracker.
# == Schema Information
#
# Table name: crm_user_days
#
#  id            :bigint           not null, primary key
#  day           :date             not null
#  first_seen_at :datetime         not null
#  hits          :integer          default(1), not null
#  last_seen_at  :datetime         not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_crm_user_days_on_account_id_and_day              (account_id,day)
#  index_crm_user_days_on_account_id_and_user_id_and_day  (account_id,user_id,day) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::UserDay < ApplicationRecord
  self.table_name = 'crm_user_days'

  belongs_to :account
  belongs_to :user
end
