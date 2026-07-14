# Uma linha por chamada de agente de IA — tokens e custo estimado (US$).
# == Schema Information
#
# Table name: crm_ai_usages
#
#  id            :bigint           not null, primary key
#  agent_key     :string           not null
#  cost_usd      :decimal(12, 6)   default(0.0), not null
#  input_tokens  :integer          default(0), not null
#  model         :string           not null
#  output_tokens :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_crm_ai_usages_on_account_id                 (account_id)
#  index_crm_ai_usages_on_account_id_and_agent_key   (account_id,agent_key)
#  index_crm_ai_usages_on_account_id_and_created_at  (account_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::AiUsage < ApplicationRecord
  self.table_name = 'crm_ai_usages'

  belongs_to :account

  validates :agent_key, :model, presence: true
end
