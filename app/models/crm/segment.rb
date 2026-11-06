# == Schema Information
#
# Table name: crm_segments
#
#  id           :bigint           not null, primary key
#  finished_at  :datetime
#  kind         :string           default("teste"), not null
#  last_tick_at :datetime
#  name         :string           not null
#  pace         :jsonb            not null
#  source       :jsonb            not null
#  started_at   :datetime
#  stats        :jsonb            not null
#  status       :string           default("reservado"), not null
#  variants     :jsonb            not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  creator_id   :bigint
#  parent_id    :bigint
#
# Indexes
#
#  index_crm_segments_on_account_id             (account_id)
#  index_crm_segments_on_account_id_and_status  (account_id,status)
#  index_crm_segments_on_creator_id             (creator_id)
#  index_crm_segments_on_parent_id              (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (creator_id => users.id)
#  fk_rails_...  (parent_id => crm_segments.id)
#
# 🧪 item 383: um SEGMENTO da base — pedaço nomeado e congelado (lote de teste
# com até 5 mensagens ou lote de escala com a vencedora). Ver Crm::SegmentBuilder
# (monta e reserva), Crm::SegmentSender (manda no ritmo) e Crm::SegmentResults
# (lê os números por mensagem).
class Crm::Segment < ApplicationRecord
  self.table_name = 'crm_segments'

  KINDS = %w[teste escala].freeze
  STATUSES = %w[reservado enviando pausado concluido].freeze
  MAX_VARIANTS = 5

  belongs_to :account
  belongs_to :creator, class_name: 'User', optional: true
  belongs_to :parent, class_name: 'Crm::Segment', optional: true
  has_many :members, class_name: 'Crm::SegmentMember', dependent: :delete_all, inverse_of: :segment
  has_many :children, class_name: 'Crm::Segment', foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :sending, -> { where(status: 'enviando') }

  def teste? = kind == 'teste'
  def escala? = kind == 'escala'
  def sending? = status == 'enviando'
  def reserved? = status == 'reservado'
  def done? = status == 'concluido'

  def variant(key)
    Array(variants).find { |v| v['key'] == key.to_s }
  end

  # ainda dá para mexer nas mensagens? só enquanto ninguém recebeu
  def editable_variants?
    !members.where.not(status: 'reservado').exists?
  end

  def remaining
    members.where(status: 'reservado').count
  end
end
