# Uma RECOMENDAÇÃO do Agente de Campanhas (item 352) e o que aconteceu com ela:
#   suggested  esperando o ok de alguém
#   approved   aprovada; falta aplicar (pela API da Meta ou à mão no Gerenciador)
#   applied    aplicada em applied_at (api | manual) — daqui sai o antes × depois
#   dismissed  descartada (a regra não volta a sugerir a mesma coisa por uns dias)
#   expired    ficou aberta tempo demais e perdeu a validade
# == Schema Information
#
# Table name: cevico_campaign_actions
#
#  id             :bigint           not null, primary key
#  applied_at     :datetime
#  applied_mode   :string
#  campaign_name  :string
#  channel        :string           not null
#  decided_at     :datetime
#  error          :text
#  evidence       :text
#  expected       :string
#  key            :string           not null
#  kind           :string           not null
#  learned_at     :datetime
#  level          :string           not null
#  metrics_after  :jsonb            not null
#  metrics_before :jsonb            not null
#  outcome        :string
#  payload        :jsonb            not null
#  ref_name       :string
#  rule           :string           not null
#  severity       :string           default("atencao"), not null
#  status         :string           default("suggested"), not null
#  suggested_on   :date             not null
#  suggestion     :text
#  title          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  campaign_id    :string
#  decided_by_id  :bigint
#  ref_id         :string           not null
#
# Indexes
#
#  idx_on_account_id_channel_ref_id_a77366bd7c             (account_id,channel,ref_id)
#  idx_on_account_id_key_suggested_on_041bac315a           (account_id,key,suggested_on)
#  index_cevico_campaign_actions_on_account_id             (account_id)
#  index_cevico_campaign_actions_on_account_id_and_status  (account_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::CampaignAction < ApplicationRecord
  self.table_name = 'cevico_campaign_actions'

  STATUSES = %w[suggested approved applied dismissed expired].freeze
  # item 353: o Agente de Páginas usa a mesma fila (canal 'pages'): seo, content e traffic
  KINDS = %w[pause budget_up budget_down new_creative audience page quality pacing watch seo content traffic].freeze
  SEVERITIES = %w[alerta atencao oportunidade info seo].freeze
  OUTCOMES = %w[better worse same saved early].freeze
  OPEN = %w[suggested approved].freeze
  # recomendações que mudam algo NA PLATAFORMA (as outras são "faça à mão": criativo, público, página…)
  PLATFORM_KINDS = %w[pause budget_up budget_down].freeze

  belongs_to :account

  validates :channel, :level, :ref_id, :rule, :kind, :key, :title, :suggested_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

  scope :open, -> { where(status: OPEN) }
  scope :pages, -> { where(channel: 'pages') }
  scope :ads, -> { where(channel: %w[meta google]) }
  scope :recent, -> { order(suggested_on: :desc, id: :desc) }

  def open? = OPEN.include?(status)
  def platform? = PLATFORM_KINDS.include?(kind)

  def as_json(_options = nil) # rubocop:disable Metrics/AbcSize
    {
      id: id, channel: channel, level: level, ref_id: ref_id, ref_name: ref_name,
      campaign_id: campaign_id, campaign_name: campaign_name,
      rule: rule, kind: kind, severity: severity, status: status, key: key,
      title: title, evidence: evidence, suggestion: suggestion, expected: expected,
      payload: payload, metrics_before: metrics_before, metrics_after: metrics_after, outcome: outcome,
      suggested_on: suggested_on&.iso8601, decided_at: decided_at&.iso8601, decided_by_id: decided_by_id,
      applied_at: applied_at&.iso8601, applied_mode: applied_mode, learned_at: learned_at&.iso8601,
      error: error, platform: platform?
    }
  end
end
