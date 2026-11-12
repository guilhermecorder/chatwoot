# 📄 Um orçamento gerado no Gerador de proposta (LIFE): os números do DRE, o preço (padrão ou
# ajustado na mão), as cotações usadas e os documentos (proposta, justificativa, card de resumo).
# Fica guardado por cliente; `sent_at` marca quando a proposta foi enviada.
#
# payload: { 'cliente', 'conta', 'telhado', 'opcao', 'cotacoes', 'dre', 'proposta', 'justificativa' }
# == Schema Information
#
# Table name: crm_quotes
#
#  id            :bigint           not null, primary key
#  delete_reason :string
#  deleted_at    :datetime
#  kind          :string
#  margin        :decimal(6, 4)
#  payload       :jsonb            not null
#  price         :decimal(12, 2)   default(0.0), not null
#  sent_at       :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  contact_id    :bigint           not null
#  deleted_by_id :bigint
#  user_id       :bigint
#
# Indexes
#
#  index_crm_quotes_on_account_id_and_contact_id_and_created_at  (account_id,contact_id,created_at)
#  index_crm_quotes_on_account_id_and_deleted_at                 (account_id,deleted_at)
#
class Crm::Quote < ApplicationRecord
  self.table_name = 'crm_quotes'

  belongs_to :account
  belongs_to :contact, class_name: '::Contact'
  belongs_to :user, optional: true

  has_many_attached :files

  validates :price, numericality: { greater_than: 0 }

  belongs_to :deleted_by, class_name: 'User', optional: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  # 🗑️ lixeira (12/11): excluir só marca; os PDFs ficam e o dono da conta restaura
  scope :ativos, -> { where(deleted_at: nil) }
  scope :na_lixeira, -> { where.not(deleted_at: nil) }

  def trash!(user, reason)
    update!(deleted_at: Time.current, deleted_by: user, delete_reason: reason.to_s.strip.first(300).presence)
  end

  def restore!
    update!(deleted_at: nil, deleted_by: nil, delete_reason: nil)
  end

  def trashed?
    deleted_at.present?
  end

  def sent?
    sent_at.present?
  end

  # Anexa os arquivos devolvidos pelo gerador de PDF: [{ 'nome', 'tipo', 'base64' }]
  def attach_rendered(rendered)
    Array(rendered).each do |file|
      files.attach(io: StringIO.new(Base64.decode64(file['base64'].to_s)), filename: file['nome'].to_s, content_type: file['tipo'].to_s)
    end
  end
end
