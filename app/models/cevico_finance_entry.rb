# Um lançamento financeiro da clínica (Gestão Financeira, só admin).
# Tipos de ENTRADA (receita) e SAÍDA (tributo, custo, investimentos);
# cada tipo tem as suas subcategorias oficiais.
# == Schema Information
#
# Table name: cevico_finance_entries
#
#  id            :bigint           not null, primary key
#  amount        :decimal(12, 2)   default(0.0), not null
#  category      :string
#  description   :string           default(""), not null
#  entry_date    :date             not null
#  kind          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :integer
#
# Indexes
#
#  index_cevico_finance_entries_on_account_id                 (account_id)
#  index_cevico_finance_entries_on_account_id_and_entry_date  (account_id,entry_date)
#  index_cevico_finance_entries_on_account_id_and_kind        (account_id,kind)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CevicoFinanceEntry < ApplicationRecord
  belongs_to :account

  # tipo => rótulo humano (fluxo: receita entra, o resto sai do caixa)
  KINDS = {
    'receita' => 'Receita',
    'tributo' => 'Tributos',
    'custo' => 'Custos',
    'investimento_produto' => 'Produto & Estoque',
    'investimento_equipamento' => 'Equipamentos'
  }.freeze

  CATEGORIES = {
    'receita' => {
      'consultas' => 'Consultas',
      'cirurgias' => 'Cirurgias',
      'exames' => 'Exames',
      'convenios' => 'Convênios',
      'outras' => 'Outras receitas'
    },
    'tributo' => {
      'impostos' => 'Impostos',
      'taxas' => 'Taxas e contribuições',
      'outros' => 'Outros tributos'
    },
    'custo' => {
      'servicos' => 'Serviços',
      'comissoes' => 'Comissões',
      'distribuicao_lucros' => 'Distribuição de lucros',
      'servicos_medicos' => 'Serviços médicos',
      'sala_cirurgica' => 'Sala cirúrgica',
      'outros' => 'Outros custos'
    },
    'investimento_produto' => {
      'lentes' => 'Lentes',
      'insumos' => 'Insumos',
      'medicamentos' => 'Medicamentos',
      'estoque' => 'Estoque geral'
    },
    'investimento_equipamento' => {
      'equipamentos' => 'Equipamentos',
      'manutencao' => 'Manutenção',
      'tecnologia' => 'Tecnologia & software'
    }
  }.freeze

  validates :entry_date, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :amount, numericality: { greater_than: 0 }

  scope :in_period, ->(from, to) { where(entry_date: from..to) }
  scope :of_kind, ->(kind) { where(kind: kind) }
end
