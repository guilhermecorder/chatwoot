# Métricas de UM anúncio em UM dia, como a Meta devolve (level=ad,
# time_increment=1), já normalizadas em `metrics`. Item 172.
# == Schema Information
#
# Table name: cevico_ad_insights
#
#  id         :bigint           not null, primary key
#  date       :date             not null
#  metrics    :jsonb            not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  ad_id      :string           not null
#
# Indexes
#
#  index_cevico_ad_insights_on_account_id                     (account_id)
#  index_cevico_ad_insights_on_account_id_and_ad_id_and_date  (account_id,ad_id,date) UNIQUE
#  index_cevico_ad_insights_on_account_id_and_date            (account_id,date)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::AdInsight < ApplicationRecord
  self.table_name = 'cevico_ad_insights'

  belongs_to :account

  validates :ad_id, :date, presence: true

  scope :between, ->(since_date, until_date) { where(date: since_date..until_date) }

  METRIC_KEYS = %w[spend impressions reach frequency clicks link_clicks plays_3s plays_2s thruplay
                   p25 p50 p75 p100 avg_watch conversations first_replies leads post_engagement].freeze
end
