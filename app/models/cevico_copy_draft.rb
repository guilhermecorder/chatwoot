# 🪝 item 397: uma CRIAÇÃO montada no Banco de Ganchos (gancho → história →
# oferta, com os reganchos que entraram no meio) e o texto final.
# == Schema Information
#
# Table name: cevico_copy_drafts
#
#  id          :bigint           not null, primary key
#  formato     :string
#  partes      :jsonb            not null
#  status      :string           default("rascunho"), not null
#  tema        :string
#  texto_final :text
#  titulo      :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  creator_id  :bigint
#
# Indexes
#
#  index_cevico_copy_drafts_on_account_id                 (account_id)
#  index_cevico_copy_drafts_on_account_id_and_created_at  (account_id,created_at)
#  index_cevico_copy_drafts_on_creator_id                 (creator_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (creator_id => users.id)
#
class CevicoCopyDraft < ApplicationRecord
  belongs_to :account
  belongs_to :creator, class_name: 'User', optional: true

  STATUSES = %w[rascunho aprovado publicado].freeze
  FORMATOS = %w[reels carrossel anuncio post].freeze

  validates :titulo, presence: true
  validates :status, inclusion: { in: STATUSES }
end
