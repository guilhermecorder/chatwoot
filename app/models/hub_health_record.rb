# Um registro de saúde do HUB (segmento saude): um treino feito, o diário
# alimentar de um dia ou uma medição do corpo. O conteúdo vai em data
# (jsonb) — o formato de cada tipo é definido pelo HealthController.
# == Schema Information
#
# Table name: hub_health_records
#
#  id          :bigint           not null, primary key
#  data        :jsonb            not null
#  kind        :string           not null
#  record_date :date             not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  user_id     :integer
#
# Indexes
#
#  idx_on_account_id_kind_record_date_d8c9fb4010  (account_id,kind,record_date)
#  index_hub_health_records_on_account_id         (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class HubHealthRecord < ApplicationRecord
  belongs_to :account

  # profile = ficha da pessoa (peso-alvo, sessões/semana) — 1 por usuário
  KINDS = %w[workout boxing diet body profile].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :record_date, presence: true

  scope :of_kind, ->(kind) { where(kind: kind) }
  scope :recent_first, -> { order(record_date: :desc, id: :desc) }
end
