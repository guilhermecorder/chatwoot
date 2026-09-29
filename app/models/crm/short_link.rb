# 🔗 Link curto (item 302): código de 10 letras → token fechado que já existia.
# Quem decide o que o link mostra continua sendo o TOKEN (cifrado e assinado);
# o código é só o apelido dele no endereço. Código que não existe, vencido ou
# de outro tipo = link vencido.
# == Schema Information
#
# Table name: cevico_short_links
#
#  id         :bigint           not null, primary key
#  code       :string           not null
#  expires_at :datetime         not null
#  kind       :string           not null
#  token      :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_cevico_short_links_on_account_id  (account_id)
#  index_cevico_short_links_on_code        (code) UNIQUE
#  index_cevico_short_links_on_expires_at  (expires_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::ShortLink < ApplicationRecord
  self.table_name = 'cevico_short_links'

  CODE_SIZE = 10

  belongs_to :account

  validates :code, presence: true, uniqueness: true
  validates :kind, :token, :expires_at, presence: true

  scope :live, -> { where('expires_at > ?', Time.current) }

  def self.shorten!(account:, kind:, token:, expires_at:)
    where(expires_at: ...Time.current).delete_all # faxina dos vencidos
    attempts = 0
    begin
      create!(account: account, kind: kind.to_s, token: token, expires_at: expires_at, code: SecureRandom.alphanumeric(CODE_SIZE))
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      retry if (attempts += 1) < 5
      raise
    end
  end

  def self.token_for(code, kind:)
    return nil unless code.to_s.match?(/\A[A-Za-z0-9]{#{CODE_SIZE}}\z/o)

    live.find_by(code: code.to_s, kind: kind.to_s)&.token
  end
end
