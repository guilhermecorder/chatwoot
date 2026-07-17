# Card do PLANEJAMENTO DE CONTEÚDOS (workflow de marketing): uma peça de
# conteúdo (reels, carrossel, post, anúncio, página, e-mail) andando pelo
# fluxo ideia → copy → produção → revisão → publicado.
# == Schema Information
#
# Table name: cevico_content_items
#
#  id         :bigint           not null, primary key
#  due_on     :date
#  format     :string           default("post"), not null
#  notes      :text
#  position   :integer          default(0), not null
#  stage      :string           default("ideia"), not null
#  title      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  owner_id   :integer
#
# Indexes
#
#  index_cevico_content_items_on_account_id            (account_id)
#  index_cevico_content_items_on_account_id_and_stage  (account_id,stage)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CevicoContentItem < ApplicationRecord
  belongs_to :account

  FORMATS = %w[reels carrossel post anuncio pagina email].freeze
  STAGES = %w[ideia copy producao revisao publicado].freeze

  validates :title, presence: true
  validates :format, inclusion: { in: FORMATS }
  validates :stage, inclusion: { in: STAGES }
end
