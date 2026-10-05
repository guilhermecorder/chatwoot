# 🏷️ FONTE DE PACIENTES (item 322, 04/10). Pedido do Guilherme: "quero ser
# capaz de gerenciar pacientes de diversas fontes; cada fonte de clientes com o
# seu ambiente isolado" — começando pelo Oftalmofácil.
#
# Cada fonte é DONA de um ambiente: os seus funis do CRM e as suas caixas de
# entrada (config.pipeline_ids / config.inbox_ids). A fonte da casa (`own`,
# chave `cevico`) fica com tudo o que nenhuma outra fonte pegou.
#
# Oftalmofácil (chave `oftalmofacil`): enquanto a cerca dos parceiros (item
# 231) for quem manda, o funil e as caixas dela continuam vindo do card do
# OftalmoFácil em Integrações — uma verdade só, sem cadastro em dois lugares.
#
# == Schema Information
#
# Table name: cevico_sources
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  color      :string
#  config     :jsonb            not null
#  key        :string           not null
#  kind       :string           default("partner"), not null
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_cevico_sources_on_account_id_and_key  (account_id,key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::Source < ApplicationRecord
  self.table_name = 'cevico_sources'

  KINDS = %w[own partner].freeze
  OWN_KEY = 'cevico'.freeze
  PARTNER_KEY = 'oftalmofacil'.freeze

  belongs_to :account

  validates :name, presence: true, length: { maximum: 60 }
  validates :key, presence: true, format: { with: /\A[a-z0-9_]{2,40}\z/ }, uniqueness: { scope: :account_id }
  validates :kind, inclusion: { in: KINDS }

  after_commit { Crm::Sources.forget!(account) }

  scope :ordered, -> { order(:position, :id) }

  def own?
    kind == 'own'
  end

  # a fonte cujo ambiente ainda é configurado no card do OftalmoFácil
  def legacy_partner?
    key == PARTNER_KEY
  end

  def pipeline_ids
    ids = Array(config['pipeline_ids']).map(&:to_i)
    ids |= [Crm::PartnerGuard.partner_pipeline_id(account)].compact if legacy_partner?
    ids.select(&:positive?)
  end

  def inbox_ids
    ids = Array(config['inbox_ids']).map(&:to_i)
    ids |= Crm::PartnerGuard.partner_inbox_ids(account) if legacy_partner?
    ids.select(&:positive?)
  end
end
