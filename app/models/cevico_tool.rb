# Uma FERRAMENTA da Academia: texto de trabalho escrito pelo admin
# (script, método, checklist) que o time lê em página bonita.
# Rascunho (published: false) só aparece para o admin.
# == Schema Information
#
# Table name: cevico_tools
#
#  id            :bigint           not null, primary key
#  category      :string           default(""), not null
#  content       :text             default(""), not null
#  emoji         :string           default("🧰"), not null
#  position      :integer          default(0), not null
#  published     :boolean          default(TRUE), not null
#  title         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :integer
#
# Indexes
#
#  index_cevico_tools_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CevicoTool < ApplicationRecord
  belongs_to :account

  validates :title, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position, :id) }
end
