# Página pública CEVICO (ambiente Páginas): anuncia procedimentos, quebra
# objeções e nutre o paciente por estágio da jornada. Publicada em /p/:slug
# com meta tags próprias (preparada para ranquear SEO: cirurgia de catarata,
# refrativa, lasik, prk, artisan, lentes...).
# == Schema Information
#
# Table name: cevico_pages
#
#  id                :bigint           not null, primary key
#  ab_variants       :jsonb            not null
#  body              :text
#  category          :string           default("captacao"), not null
#  color             :string
#  cta_clicks_count  :integer          default(0), not null
#  cta_label         :string
#  cta_url           :string
#  custom_html       :text
#  daily_stats       :jsonb            not null
#  emoji             :string
#  meta_description  :text
#  meta_title        :string
#  next_clicks_count :integer          default(0), not null
#  sections          :jsonb            not null
#  seo_keywords      :string
#  slug              :string           not null
#  status            :string           default("draft"), not null
#  subtitle          :string
#  team_comments     :jsonb            not null
#  title             :string           not null
#  views_count       :bigint           default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  next_page_id      :bigint
#
# Indexes
#
#  index_cevico_pages_on_account_id               (account_id)
#  index_cevico_pages_on_account_id_and_category  (account_id,category)
#  index_cevico_pages_on_next_page_id             (next_page_id)
#  index_cevico_pages_on_slug                     (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (next_page_id => cevico_pages.id)
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

  # gestão de projetos de página (pedido 17/07): ideia → em produção →
  # publicada. Só 'published' aparece ao público.
  STATUSES = {
    'idea' => '💡 Ideia',
    'draft' => '🛠 Em produção',
    'published' => '🟢 Publicada'
  }.freeze

  # funil de páginas: o CTA pode reapontar pra outra página da CEVICO
  belongs_to :next_page, class_name: 'CevicoPage', optional: true

  # exclusão: leva junto os baldes de tráfego e os Protocolos (FKs NOT NULL
  # travariam o DELETE) e solta quem apontava pra ela como próximo passo
  has_many :traffic_rows, class_name: 'CevicoPageTraffic', dependent: :delete_all
  has_many :refs, class_name: 'CevicoPageRef', dependent: :delete_all
  has_many :funnel_prev_pages, class_name: 'CevicoPage', foreign_key: :next_page_id,
                               dependent: :nullify, inverse_of: :next_page

  validates :title, presence: true
  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  # caminhos que já pertencem ao sistema — no domínio oficial a página mora
  # na RAIZ (www.cevico.com.br/slug), então o slug não pode colidir com rota real
  RESERVED_SLUGS = %w[app api auth forms p widget survey health packs assets
                      vite rails brand-assets audio downloads super_admin
                      installation swagger monitoring sitemap robots].freeze

  validates :slug, presence: true, uniqueness: true,
                   exclusion: { in: RESERVED_SLUGS, message: 'esse endereço é reservado do sistema' }, # rubocop:disable Rails/I18nLocaleTexts
                   format: { with: /\A[a-z0-9-]+\z/, message: 'só letras minúsculas, números e hífens' } # rubocop:disable Rails/I18nLocaleTexts

  before_validation :generate_slug, on: :create

  scope :published, -> { where(status: 'published') }

  def published?
    status == 'published'
  end

  # ── Prévia do RASCUNHO (pedido 23/07) ──
  # Link secreto do admin: quem tem o link vê a página antes de publicar,
  # em qualquer domínio, sem login. O token é assinado pelo segredo do
  # servidor — não dá pra forjar nem adivinhar.
  def preview_token
    Rails.application.message_verifier('cevico-page-preview').generate(id)
  end

  def self.find_by_preview_token(token)
    id = Rails.application.message_verifier('cevico-page-preview').verify(token.to_s)
    find_by(id: id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  # token de RETOQUE (23/07): separado do de visualização — quem recebe o
  # link da prévia só OLHA; editar inline exige este token, que apenas o
  # time logado recebe (vem no builder_url do admin)
  def edit_token
    Rails.application.message_verifier('cevico-page-edit').generate(id)
  end

  def valid_edit_token?(token)
    Rails.application.message_verifier('cevico-page-edit').verify(token.to_s) == id
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    false
  end

  # seções vindas da IA (montagem em segundo plano): só tipos/efeitos
  # conhecidos e textos com limite — a página pública confia no banco
  def self.normalize_ai_sections(sections)
    Array(sections).filter_map do |sec|
      sec = sec.to_h.deep_stringify_keys
      next unless SECTION_TYPES.include?(sec['type'])

      {
        'type' => sec['type'],
        'effect' => SECTION_EFFECTS.include?(sec['effect']) ? sec['effect'] : 'nenhum',
        'title' => sec['title'].to_s[0, 200],
        'text' => sec['text'].to_s[0, 4000],
        # retoques que a IA agora também controla — mesma régua do editor
        'color' => sec['color'].to_s.match?(/\A#[0-9A-Fa-f]{6}\z/) ? sec['color'] : nil,
        'image_url' => sec['image_url'].to_s.start_with?('/rails/active_storage/') ? sec['image_url'] : nil,
        'items' => Array(sec['items']).map do |it|
          it = it.to_h.deep_stringify_keys
          { 'title' => it['title'].to_s[0, 200], 'text' => it['text'].to_s[0, 1000] }
        end
      }
    end
  end

  # retoque inline no rascunho (estilo "clica e edita"): SÓ textos —
  # tipo/efeito/cor/imagem/ordem ficam como estão (esses são do editor)
  def apply_inline_edits!(edits) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    edits = edits.to_h.deep_stringify_keys
    attrs = {}
    attrs[:title] = edits['title'].to_s.strip[0, 200] if edits['title'].present?
    attrs[:subtitle] = edits['subtitle'].to_s.strip[0, 300] if edits.key?('subtitle')
    attrs[:cta_label] = edits['cta_label'].to_s.strip[0, 120] if edits.key?('cta_label')
    if edits['sections'].is_a?(Hash) && sections.present?
      attrs[:sections] = sections.map.with_index do |sec, i|
        patch = edits['sections'][i.to_s]
        next sec unless patch.is_a?(Hash)

        merged = sec.dup
        merged['title'] = patch['title'].to_s[0, 200] if patch.key?('title') && !patch['title'].nil?
        merged['text'] = patch['text'].to_s[0, 4000] if patch.key?('text') && !patch['text'].nil?
        if patch['items'].is_a?(Hash) && merged['items'].is_a?(Array)
          merged['items'] = merged['items'].map.with_index do |item, j|
            item_patch = patch['items'][j.to_s]
            next item unless item_patch.is_a?(Hash)

            item.merge(
              item_patch.key?('title') ? { 'title' => item_patch['title'].to_s[0, 200] } : {},
              item_patch.key?('text') ? { 'text' => item_patch['text'].to_s[0, 1000] } : {}
            )
          end
        end
        merged
      end
    end
    update!(attrs) if attrs.any?
  end

  # corpo (markdown) → HTML seguro para a página pública
  def body_html
    return '' if body.blank?

    CommonMarker.render_html(body, :DEFAULT, [:table, :strikethrough, :autolink])
  end

  # ── Testes A/B (PÁGINAS PRO) ─────────────────────────────────────────
  # Variações de headline/CTA servidas alternadamente NO MESMO slug.
  # A variação "a" é a própria página; as demais vivem em ab_variants:
  # [{ key: 'b', name: 'Variação B', title:, subtitle:, cta_label:, active: }]
  # O visitante que entra num teste carrega ?v= nos cliques — assim cada
  # visita/clique/conversão é contado POR VARIAÇÃO no daily_stats.
  attr_accessor :serving_variant

  def active_variants
    Array(ab_variants).select { |v| v['active'] }
  end

  def ab_test_running?
    published? && active_variants.any?
  end

  # sorteia quem o visitante vai ver ('a' = original)
  def pick_variant
    (['a'] + active_variants.pluck('key')).sample
  end

  def variant_field(field)
    return nil if serving_variant.blank? || serving_variant == 'a'

    active_variants.find { |v| v['key'] == serving_variant }&.dig(field).presence
  end

  def display_title
    variant_field('title') || title
  end

  def display_subtitle
    variant_field('subtitle') || subtitle
  end

  AB_KINDS = %w[view cta next].freeze

  # placar consolidado do teste (todas as datas do daily_stats)
  def ab_results
    keys = ['a'] + Array(ab_variants).pluck('key')
    totals = keys.index_with { { 'view' => 0, 'cta' => 0, 'next' => 0 } }
    (daily_stats || {}).each_value do |day|
      keys.each do |key|
        AB_KINDS.each { |kind| totals[key][kind] += day["#{kind}_#{key}"].to_i }
      end
    end
    totals
  end

  # ── Funil + rastreamento (pedido 17/07) ─────────────────────────────
  # O botão da página aponta pro PRÓXIMO PASSO: outra página CEVICO
  # (funil de conteúdo) ou o convite normal (WhatsApp/cta_url). Os dois
  # passam pelo redirecionador que CONTA o clique.
  def funnel_target
    next_page if next_page&.published?
  end

  def cta_href
    base = if funnel_target
             "/p/#{slug}/next"
           elsif cta_url.present?
             "/p/#{slug}/cta"
           end
    return base if base.nil? || serving_variant.blank? || serving_variant == 'a'

    # visitante do teste A/B carrega a variação no clique
    "#{base}?v=#{serving_variant}"
  end

  def cta_text
    return variant_field('cta_label') if variant_field('cta_label')
    return cta_label if cta_label.present?
    return "Continuar: #{funnel_target.title} →" if funnel_target

    'Falar com a CEVICO no WhatsApp'
  end

  COUNTER_BY_KIND = { 'view' => :views_count, 'cta' => :cta_clicks_count, 'next' => :next_clicks_count }.freeze

  # soma 1 no contador do dia (e no total). `source` = slug da página de
  # origem quando o visitante chegou pelo funil (?de=slug); `variant` =
  # letra do teste A/B em curso (conta também por variação)
  def track_hit!(kind, source: nil, variant: nil)
    stats = daily_stats.presence || {}
    day = (stats[Date.current.iso8601] ||= {})
    day[kind.to_s] = day[kind.to_s].to_i + 1
    day["#{kind}_#{variant}"] = day["#{kind}_#{variant}"].to_i + 1 if variant.present?
    record_origin(day, source)
    updates = { daily_stats: stats }
    counter = COUNTER_BY_KIND[kind.to_s]
    updates[counter] = self[counter].to_i + 1 if counter
    update_columns(updates) # rubocop:disable Rails/SkipsModelValidations
  end

  # profundidade de rolagem (25/50/75/100) — beacon leve da página pública
  def track_scroll!(bucket)
    return unless %w[25 50 75 100].include?(bucket.to_s)

    stats = daily_stats.presence || {}
    day = (stats[Date.current.iso8601] ||= {})
    scroll = (day['scroll'] ||= {})
    scroll[bucket.to_s] = scroll[bucket.to_s].to_i + 1
    update_columns(daily_stats: stats) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  # marca de qual página do funil o visitante veio ({"de" => {slug => n}})
  def record_origin(day, source)
    clean = source.to_s.gsub(/[^a-z0-9-]/, '')[0, 60]
    return if clean.blank?

    origins = (day['de'] ||= {})
    origins[clean] = origins[clean].to_i + 1
  end

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
