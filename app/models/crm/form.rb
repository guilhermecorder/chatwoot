# Formulário dinâmico da CEVICO (ex: perguntas pré-operatórias).
# O admin monta as perguntas; o paciente responde por link público
# assinado (sem login); as respostas caem amarradas ao contato.
#
# Formato de cada pergunta em `questions`:
#   { "id" => "q1", "label" => "...", "type" => "choice|multi|text|scale|yesno",
#     "options" => ["...", ...], "required" => true }
# == Schema Information
#
# Table name: crm_forms
#
#  id             :bigint           not null, primary key
#  active         :boolean          default(TRUE), not null
#  ai_insight     :jsonb            not null
#  intro_text     :text
#  intro_title    :string
#  name           :string           not null
#  questions      :jsonb            not null
#  slug           :string           not null
#  thank_you_text :text
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_crm_forms_on_account_id  (account_id)
#  index_crm_forms_on_slug        (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::Form < ApplicationRecord
  self.table_name = 'crm_forms'

  belongs_to :account
  has_many :responses, class_name: 'Crm::FormResponse', foreign_key: :crm_form_id, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :ensure_slug, on: :create

  QUESTION_TYPES = %w[choice multi text scale yesno].freeze

  # link público único por contato: o token assinado identifica
  # formulário + contato sem expor nenhum id
  def public_link_for(contact)
    token = Rails.application.message_verifier(:cevico_form).generate(
      { form_id: id, account_id: account_id, contact_id: contact&.id }
    )
    "#{base_url}/forms/#{slug}/#{CGI.escape(token)}"
  end

  def self.verify_token(token)
    Rails.application.message_verifier(:cevico_form).verify(token)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  private

  def ensure_slug
    return if slug.present?

    base = name.to_s.parameterize.presence || 'form'
    self.slug = "#{base}-#{SecureRandom.alphanumeric(6).downcase}"
  end

  def base_url
    ENV.fetch('FRONTEND_URL', '').chomp('/')
  end
end
