# == Schema Information
#
# Table name: crm_segment_members
#
#  id              :bigint           not null, primary key
#  frente          :string
#  sent_at         :datetime
#  status          :string           default("reservado"), not null
#  variant_key     :string           default("A"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  campaign_id     :bigint
#  contact_id      :bigint           not null
#  conversation_id :bigint
#  inbox_id        :bigint
#  segment_id      :bigint           not null
#
# Indexes
#
#  index_crm_segment_members_on_campaign_id                (campaign_id)
#  index_crm_segment_members_on_contact_id                 (contact_id) UNIQUE
#  index_crm_segment_members_on_conversation_id            (conversation_id)
#  index_crm_segment_members_on_segment_id                 (segment_id)
#  index_crm_segment_members_on_segment_id_and_contact_id  (segment_id,contact_id) UNIQUE
#  index_crm_segment_members_on_segment_id_and_status      (segment_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (campaign_id => crm_campaigns.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (segment_id => crm_segments.id)
#
# 🧪 item 383: uma PESSOA dentro de um segmento, com a mensagem sorteada para
# ela (variant_key) e o que aconteceu: reservada → enviada (ou falhou/pulada).
class Crm::SegmentMember < ApplicationRecord
  self.table_name = 'crm_segment_members'

  STATUSES = %w[reservado enviando enviado falhou pulado].freeze

  belongs_to :segment, class_name: 'Crm::Segment', inverse_of: :members
  belongs_to :contact, class_name: '::Contact'
  belongs_to :campaign, class_name: 'Crm::Campaign', optional: true
  belongs_to :conversation, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :contact_id, uniqueness: { scope: :segment_id }

  scope :reserved, -> { where(status: 'reservado') }
  scope :sent, -> { where(status: 'enviado') }
  # quem "segura" a pessoa: na fila, saindo ou já recebeu (pulado/falhou liberam a pessoa)
  scope :holding, -> { where(status: %w[reservado enviando enviado]) }
end
