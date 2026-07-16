# Página pública CEVICO (ambiente Páginas): anuncia procedimentos, quebra
# objeções e nutre o paciente por estágio da jornada. Publicada em /p/:slug
# com meta tags próprias (preparada para ranquear SEO: cirurgia de catarata,
# refrativa, lasik, prk, artisan, lentes...).
# == Schema Information
#
# Table name: cevico_pages
#
#  id               :bigint           not null, primary key
#  body             :text
#  category         :string           default("captacao"), not null
#  color            :string
#  cta_label        :string
#  cta_url          :string
#  emoji            :string
#  meta_description :text
#  meta_title       :string
#  sections         :jsonb            not null
#  slug             :string           not null
#  status           :string           default("draft"), not null
#  subtitle         :string
#  title            :string           not null
#  views_count      :bigint           default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_cevico_pages_on_account_id               (account_id)
#  index_cevico_pages_on_account_id_and_category  (account_id,category)
#  index_cevico_pages_on_slug                     (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class CevicoPage < ApplicationRecord
  belongs_to :account

  CATEGORIES = {
    'captacao' => 'Procedimentos — Captação',
    'pre_consulta' => 'Procedimentos — Pacientes pré consulta',
    'pre_cirurgia' => 'Procedimentos — Pacientes pré cirurgia',
    'pos_operatorio' => 'Procedimentos — Pacientes pós operatório'
  }.freeze

  # Construtor v2: tipos de seção e efeitos visuais disponíveis.
  # Cada seção: { type, effect, title, text, items: [{ title, text }] }
  # "visao" = experiência interativa de como o paciente enxerga (miopia/
  # astigmatismo) e como fica após a correção — conexão emocional.
  SECTION_TYPES = %w[hero texto beneficios passos faq depoimento visao cta].freeze
  SECTION_EFFECTS = %w[nenhum liquido foco movimento miopia astigmatismo brilho].freeze

  validates :title, presence: true
  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :status, inclusion: { in: %w[draft published] }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/, message: 'só letras minúsculas, números e hífens' } # rubocop:disable Rails/I18nLocaleTexts

  before_validation :generate_slug, on: :create

  scope :published, -> { where(status: 'published') }

  def published?
    status == 'published'
  end

  # corpo (markdown) → HTML seguro para a página pública
  def body_html
    return '' if body.blank?

    CommonMarker.render_html(body, :DEFAULT, [:table, :strikethrough, :autolink])
  end

  private

  def generate_slug
    return if slug.present?

    base = title.to_s.parameterize
    candidate = base
    counter = 2
    while CevicoPage.exists?(slug: candidate)
      candidate = "#{base}-#{counter}"
      counter += 1
    end
    self.slug = candidate
  end
end
