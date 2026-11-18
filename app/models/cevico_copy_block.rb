# 🪝 item 397: uma PEÇA do Banco de Ganchos (gancho, história, oferta ou
# regancho). Ver a migration CreateCevicoCopyBank para o porquê.
# == Schema Information
#
# Table name: cevico_copy_blocks
#
#  id         :bigint           not null, primary key
#  categoria  :string
#  exemplo    :text
#  favorito   :boolean          default(FALSE), not null
#  fonte      :string           default("manual"), not null
#  kind       :string           default("gancho"), not null
#  lacunas    :jsonb            not null
#  original   :text
#  position   :integer          default(0), not null
#  referencia :string
#  saude      :string           default("pronto"), not null
#  texto      :text             not null
#  usos       :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  creator_id :bigint
#
# Indexes
#
#  index_cevico_copy_blocks_on_account_id                         (account_id)
#  index_cevico_copy_blocks_on_account_id_and_kind_and_categoria  (account_id,kind,categoria)
#  index_cevico_copy_blocks_on_creator_id                         (creator_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (creator_id => users.id)
#
class CevicoCopyBlock < ApplicationRecord
  belongs_to :account
  belongs_to :creator, class_name: 'User', optional: true

  KINDS = %w[gancho historia oferta regancho].freeze
  SAUDE = %w[pronto adaptar evitar].freeze

  # categorias dos ganchos (as 7 do PDF "1,000 Viral Hooks" + as da casa)
  GANCHO_CATEGORIAS = {
    'educativo' => 'Educativo',
    'comparacao' => 'Comparação',
    'quebra_de_mito' => 'Quebra de mito',
    'storytelling' => 'Storytelling',
    'aleatorio' => 'Aleatório',
    'autoridade' => 'Autoridade',
    'dia_na_vida' => 'Dia na vida',
    'cevico' => 'Da casa'
  }.freeze

  validates :texto, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :saude, inclusion: { in: SAUDE }

  before_save :fill_lacunas

  # [lacunas] do texto, na ordem, sem repetir
  def self.lacunas_de(texto)
    texto.to_s.scan(/\[([^\[\]]{1,60})\]/).flatten.map(&:strip).uniq
  end

  private

  def fill_lacunas
    self.lacunas = self.class.lacunas_de(texto)
  end
end
