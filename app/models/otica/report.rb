# 📊 Uma VERSÃO da "Análise da loja": o index.html gerado no Mac por
# OTICA/analise/savwin.py, guardado no ActiveStorage (arquivo `file`).
# A versão mais nova da conta é a que a tela mostra; as antigas ficam de
# histórico. Só administrador envia; quem vê é decidido pelo nó otica.analise.
# == Schema Information
#
# Table name: otica_reports
#
#  id            :bigint           not null, primary key
#  note          :string           default(""), not null
#  size_bytes    :integer          default(0), not null
#  title         :string           default(""), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :integer
#
# Indexes
#
#  index_otica_reports_on_account_id                 (account_id)
#  index_otica_reports_on_account_id_and_created_at  (account_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Otica::Report < ApplicationRecord
  MAX_BYTES = 10.megabytes
  TITLE_DEFAULT = 'Análise da loja'.freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_one_attached :file

  validates :title, length: { maximum: 120 }
  validates :note, length: { maximum: 300 }
  validate :file_must_be_html

  before_validation :fill_defaults

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.latest
    newest_first.first
  end

  # o HTML inteiro, como texto UTF-8 (a tela coloca num iframe sandbox)
  def html
    return '' unless file.attached?

    file.open(&:read).force_encoding(Encoding::UTF_8)
  end

  def as_json_otica
    { id: id, title: title, note: note, size_bytes: size_bytes, created_at: created_at,
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil }
  end

  private

  def fill_defaults
    self.title = TITLE_DEFAULT if title.blank?
    self.title = title.to_s.strip[0, 120]
    self.note = note.to_s.strip[0, 300]
    self.size_bytes = file.blob.byte_size if file.attached? && file.blob&.byte_size
  end

  def file_must_be_html
    return errors.add(:file, 'Envie o arquivo index.html gerado pela análise.') unless file.attached?

    return errors.add(:file, 'O arquivo é maior que 10 MB.') if file.blob&.byte_size.to_i > MAX_BYTES

    io = new_file_io
    return if io.nil? # versão já gravada: o arquivo não mudou

    head = io.read(2048).to_s.force_encoding(Encoding::UTF_8)
    io.rewind if io.respond_to?(:rewind)
    errors.add(:file, 'O arquivo não parece ser uma página HTML.') unless head.match?(/<(!doctype|html|head|body)/i)
  end

  # o conteúdo que está sendo anexado AGORA (upload da tela, da API ou de spec)
  def new_file_io
    change = attachment_changes['file']
    return nil unless change.respond_to?(:attachable)

    attachable = change.attachable
    return attachable[:io] if attachable.is_a?(Hash)
    return attachable if attachable.respond_to?(:read)

    nil
  end
end
