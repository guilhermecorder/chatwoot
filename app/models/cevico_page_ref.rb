# O "Protocolo" das Páginas: código curto gerado no clique do WhatsApp,
# vai no fim da mensagem pré-preenchida ("Protocolo: 3F9K2"). Quando a
# primeira mensagem chega na caixa com ele, o contato é carimbado com a
# página e o anúncio de origem (page_ads) — fecha o ciclo anúncio →
# página → paciente → agendou → cirurgia.
# == Schema Information
#
# Table name: cevico_page_refs
#
#  id             :bigint           not null, primary key
#  source_data    :jsonb            not null
#  token          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  cevico_page_id :bigint           not null
#  contact_id     :bigint
#
# Indexes
#
#  index_cevico_page_refs_on_account_id_and_created_at  (account_id,created_at)
#  index_cevico_page_refs_on_cevico_page_id             (cevico_page_id)
#  index_cevico_page_refs_on_contact_id                 (contact_id)
#  index_cevico_page_refs_on_token                      (token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (cevico_page_id => cevico_pages.id)
#  fk_rails_...  (contact_id => contacts.id)
#
class CevicoPageRef < ApplicationRecord
  belongs_to :account
  # sem página = Protocolo do HUB (porta de entrada na raiz do domínio)
  belongs_to :cevico_page, optional: true
  belongs_to :contact, optional: true

  # sem 0/O/1/I/L/S/5/B/8/G/Q: lido por telefone sem confusão
  TOKEN_CHARS = %w[2 3 4 6 7 9 A C D E F H J K M N P R T U V W X Y].freeze
  # protocolo vale por 90 dias — depois disso a mensagem é tratada como sem código
  VALIDITY = 90.days

  validates :token, presence: true, uniqueness: true

  scope :usable, -> { where(created_at: VALIDITY.ago..) }

  def self.mint!(page:, source_data:, account: nil)
    3.times do
      token = Array.new(5) { TOKEN_CHARS.sample }.join
      return create!(account_id: account&.id || page.account_id, cevico_page: page, token: token,
                     source_data: source_data.compact_blank)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      next
    end
    nil
  end

  # acha o protocolo dentro do texto da primeira mensagem — aceita
  # "Protocolo: 3F9K2", "protocolo 3f9k2", "#3F9K2" no fim da frase
  def self.find_in_text(account, text)
    match = text.to_s.match(/(?:protocolo[:\s#]*|#)([A-Z0-9]{5})\b/i)
    return if match.blank?

    account.cevico_page_refs.usable.find_by(token: match[1].upcase)
  end
end
