# Pilar do Painel Estratégico CEVICO: um setor do negócio (Aquisição de
# Pacientes, Operação Clínica, Financeiro/Tributário...) com responsáveis,
# status de saúde (semáforo) e as estratégias/ações corretivas dele.
# == Schema Information
#
# Table name: cevico_pillars
#
#  id          :bigint           not null, primary key
#  color       :string           default("navy")
#  emoji       :string           default("🏛️")
#  health_note :text
#  name        :string           not null
#  owner_ids   :jsonb            not null
#  position    :integer          default(0), not null
#  status      :string           default("atencao"), not null
#  subtitle    :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_cevico_pillars_on_account_id               (account_id)
#  index_cevico_pillars_on_account_id_and_position  (account_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CevicoPillar < ApplicationRecord
  belongs_to :account
  has_many :strategies, class_name: 'CevicoStrategy', foreign_key: :pillar_id,
                        dependent: :destroy, inverse_of: :pillar

  STATUSES = %w[otimo atencao critico].freeze
  COLORS = %w[navy gold emerald purple rose slate].freeze

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :color, inclusion: { in: COLORS }

  # os 3 pilares combinados com o Guilherme nascem prontos na primeira visita
  DEFAULTS = [
    { name: 'Aquisição de Pacientes', subtitle: 'Marketing e vendas — do anúncio ao agendamento',
      emoji: '🧲', color: 'navy', position: 0 },
    { name: 'Operação Clínica', subtitle: 'Exames, consultas (avaliação e pós-operatório) e procedimentos cirúrgicos',
      emoji: '🏥', color: 'emerald', position: 1 },
    { name: 'Financeiro & Tributário', subtitle: 'Caixa, custos, impostos e margem',
      emoji: '💰', color: 'gold', position: 2 }
  ].freeze

  def self.seed_defaults!(account)
    return if exists?(account: account)

    DEFAULTS.each { |attrs| create!(attrs.merge(account: account)) }
  end
end
