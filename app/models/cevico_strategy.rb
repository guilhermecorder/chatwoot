# Estratégia (ou ação corretiva) de um pilar do Painel Estratégico CEVICO:
# o que vamos fazer, quem é o dono, até quando e em que pé está.
# == Schema Information
#
# Table name: cevico_strategies
#
#  id          :bigint           not null, primary key
#  description :text
#  due_on      :date
#  kind        :string           default("estrategia"), not null
#  position    :integer          default(0), not null
#  status      :string           default("andamento"), not null
#  title       :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  owner_id    :integer
#  pillar_id   :bigint           not null
#
# Indexes
#
#  index_cevico_strategies_on_account_id           (account_id)
#  index_cevico_strategies_on_account_id_and_kind  (account_id,kind)
#  index_cevico_strategies_on_pillar_id            (pillar_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (pillar_id => cevico_pillars.id)
#
class CevicoStrategy < ApplicationRecord
  belongs_to :account
  belongs_to :pillar, class_name: 'CevicoPillar', inverse_of: :strategies

  KINDS = %w[estrategia correcao].freeze
  STATUSES = %w[ideia andamento concluida pausada].freeze

  validates :title, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
end
