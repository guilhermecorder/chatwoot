# Um dia de UMA campanha do Google (item 352): custo, cliques e impressões
# lidos do GA4 pela conta de serviço. A Meta já tem a foto diária por anúncio
# em cevico_ad_insights (Crm::AdInsight) — aqui só o Google.
# == Schema Information
#
# Table name: cevico_campaign_days
#
#  id            :bigint           not null, primary key
#  campaign_name :string
#  channel       :string           default("google"), not null
#  clicks        :integer          default(0), not null
#  date          :date             not null
#  impressions   :integer          default(0), not null
#  spend         :decimal(12, 2)   default(0.0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  campaign_id   :string           not null
#
# Indexes
#
#  index_campaign_days_unique_day                     (account_id,channel,campaign_id,date) UNIQUE
#  index_cevico_campaign_days_on_account_id           (account_id)
#  index_cevico_campaign_days_on_account_id_and_date  (account_id,date)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::CampaignDay < ApplicationRecord
  self.table_name = 'cevico_campaign_days'

  belongs_to :account

  validates :channel, :campaign_id, :date, presence: true

  scope :between, ->(since_date, until_date) { where(date: since_date..until_date) }
  scope :google, -> { where(channel: 'google') }
end
