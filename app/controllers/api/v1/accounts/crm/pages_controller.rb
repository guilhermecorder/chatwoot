# Admin do ambiente PÁGINAS: criar/editar/publicar as páginas públicas
# da clínica (nutrição de leads, quebra de objeções, procedimentos) por
# estágio da jornada. Equipe visualiza a lista; só admin mexe.
class Api::V1::Accounts::Crm::PagesController < Api::V1::Accounts::BaseController
  # o TIME inteiro cria e edita RASCUNHOS (inclusive com IA);
  # publicar/despublicar e excluir continuam com o admin
  before_action :check_admin, only: [:destroy]

  def index
    pages = Current.account.cevico_pages.order(:category, :title)
    render json: { categories: CevicoPage::CATEGORIES, pages: pages.map { |p| page_json(p) } }
  end

  def create
    page = Current.account.cevico_pages.create!(page_params)
    render json: page_json(page), status: :created
  end

  def update
    page = Current.account.cevico_pages.find(params[:id])
    page.update!(page_params)
    render json: page_json(page)
  end

  def destroy
    Current.account.cevico_pages.find(params[:id]).destroy!
    head :no_content
  end

  # IA no editor, dois modos:
  # - briefing → agente COPYWRITER escreve a página inteira em seções
  # - copy pronta → agente CONSTRUTOR monta a página sem reescrever o texto
  # O resultado volta para o editor: a pessoa revisa e salva (publicar = admin)
  def generate
    result = params[:copy].present? ? generate_from_copy : generate_from_briefing
    return render json: { error: result[:error] }, status: :unprocessable_entity if result[:error]

    render json: result
  rescue StandardError => e
    # geração nunca pode virar 500 seco na tela (bug 17/07)
    Rails.logger.error "[Pages#generate] #{e.class}: #{e.message}"
    render json: { error: "Não consegui gerar agora (#{e.class.name.demodulize}). Tente de novo em instantes." },
           status: :unprocessable_entity
  end

  # item 111 — geração em SEGUNDO PLANO: o clique agenda o trabalho e o
  # editor consulta o status a cada poucos segundos (sem conexão aberta
  # esperando a IA — era isso que dava "internet error" no proxy)
  def generate_start
    job_id = SecureRandom.hex(10)
    Redis::Alfred.setex(Crm::PageGenerateJob.result_key(job_id), { status: 'running' }.to_json, 15.minutes)
    # modo "ambiente de montagem": com page_id, o resultado vai DIRETO pra
    # página e a aba do rascunho acompanha pelo status por página
    if params[:page_id].present?
      page = Current.account.cevico_pages.find(params[:page_id])
      Redis::Alfred.setex(Crm::PageGenerateJob.page_key(page.id), { status: 'running' }.to_json, 15.minutes)
    end
    Crm::PageGenerateJob.perform_later(
      Current.account.id, job_id,
      'copy' => params[:copy].presence, 'briefing' => params[:briefing].presence,
      'category' => params[:category].presence, 'form_id' => params[:form_id].presence,
      'page_id' => params[:page_id].presence
    )
    render json: { job_id: job_id }
  end

  def generate_status
    raw = Redis::Alfred.get(Crm::PageGenerateJob.result_key(params[:job_id].to_s))
    return render json: { status: 'expired' } if raw.blank?

    render json: JSON.parse(raw)
  end

  # imagem de seção (editor de retoques, 23/07): sobe pro storage e
  # devolve o CAMINHO relativo — funciona em qualquer domínio
  def upload_image
    file = params[:image]
    return render json: { error: 'Envie uma imagem.' }, status: :unprocessable_entity if file.blank? || !file.respond_to?(:content_type)
    return render json: { error: 'Só imagens (JPG, PNG, WebP).' }, status: :unprocessable_entity unless file.content_type.to_s.start_with?('image/')
    return render json: { error: 'Imagem muito grande (máx. 8 MB).' }, status: :unprocessable_entity if file.size > 8.megabytes

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.tempfile, filename: file.original_filename, content_type: file.content_type
    )
    render json: { url: Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true) }
  end

  # ── Estúdio de copy: comentários do time na página ──
  def add_comment # rubocop:disable Metrics/AbcSize
    page = Current.account.cevico_pages.find(params[:id])
    text = params[:text].to_s.strip[0, 1000]
    return render json: { error: 'Escreva o comentário.' }, status: :unprocessable_entity if text.blank?

    comments = Array(page.team_comments)
    comments << { 'id' => SecureRandom.hex(4), 'user_id' => Current.user.id,
                  'name' => Current.user.available_name, 'text' => text,
                  'at' => Time.current.iso8601 }
    page.update!(team_comments: comments.last(100))
    render json: { team_comments: page.team_comments }
  end

  # autor apaga o próprio; admin apaga qualquer um
  def delete_comment
    page = Current.account.cevico_pages.find(params[:id])
    comments = Array(page.team_comments)
    target = comments.find { |c| c['id'] == params[:comment_id] }
    return head :not_found if target.nil?
    unless Current.account_user.administrator? || target['user_id'] == Current.user.id
      return render json: { error: 'Só o autor ou um admin apagam o comentário.' }, status: :forbidden
    end

    page.update!(team_comments: comments - [target])
    render json: { team_comments: page.team_comments }
  end

  private

  def generate_from_copy
    Crm::PageBuilderService.new(
      account: Current.account,
      copy: params[:copy].to_s,
      category: params[:category].presence || 'captacao'
    ).call
  end

  def generate_from_briefing
    form = params[:form_id].present? ? Current.account.crm_forms.find_by(id: params[:form_id]) : nil
    Crm::CopywriterService.new(
      account: Current.account,
      briefing: params[:briefing].to_s,
      category: params[:category].presence || 'captacao',
      form: form
    ).call
  end

  def check_admin
    render json: { error: 'Só administradores editam páginas.' }, status: :forbidden unless Current.account_user.administrator?
  end

  def page_params
    permitted = params.permit(:title, :slug, :category, :status, :emoji, :color, :subtitle,
                              :body, :meta_title, :meta_description, :seo_keywords,
                              :cta_label, :cta_url,
                              :next_page_id,
                              sections: [:type, :effect, :title, :text, :color, :image_url, { items: [:title, :text] }],
                              ab_variants: [:key, :name, :title, :subtitle, :cta_label, :active])
    sanitize_sections!(permitted)
    sanitize_next_page!(permitted)
    sanitize_variants!(permitted)
    # quem não é admin não muda status: cria como rascunho e nunca
    # publica/despublica (o default da coluna já é draft)
    permitted.delete(:status) unless Current.account_user.administrator?
    permitted
  end

  # só tipos/efeitos conhecidos entram no banco (a página pública confia)
  def sanitize_sections!(permitted)
    return if permitted[:sections].blank?

    permitted[:sections] = permitted[:sections].select { |sec| CevicoPage::SECTION_TYPES.include?(sec[:type]) }
    permitted[:sections].each do |sec|
      sec[:effect] = 'nenhum' unless CevicoPage::SECTION_EFFECTS.include?(sec[:effect])
      # retoques (23/07): cor = só hexadecimal; imagem = só arquivo do
      # NOSSO storage (caminho relativo) — nada de URL externa na página
      sec[:color] = nil unless sec[:color].to_s.match?(/\A#[0-9A-Fa-f]{6}\z/)
      sec[:image_url] = nil unless sec[:image_url].to_s.start_with?('/rails/active_storage/')
    end
  end

  # variações do teste A/B: chave curta minúscula, sem duplicar
  def sanitize_variants!(permitted) # rubocop:disable Metrics/AbcSize
    return if permitted[:ab_variants].blank?

    seen = []
    permitted[:ab_variants] = permitted[:ab_variants].filter_map do |v|
      key = v[:key].to_s.downcase.gsub(/[^a-z0-9]/, '')[0, 3]
      next if key.blank? || key == 'a' || seen.include?(key)

      seen << key
      { key: key, name: v[:name].to_s[0, 60], title: v[:title].to_s[0, 200],
        subtitle: v[:subtitle].to_s[0, 300], cta_label: v[:cta_label].to_s[0, 120],
        active: ActiveModel::Type::Boolean.new.cast(v[:active]) == true }
    end
  end

  # próximo passo do funil: só páginas da própria conta (vazio limpa)
  def sanitize_next_page!(permitted)
    return unless permitted.key?(:next_page_id)

    next_id = permitted[:next_page_id].presence
    permitted[:next_page_id] = next_id && Current.account.cevico_pages.exists?(id: next_id) ? next_id : nil
  end

  def page_json(page) # rubocop:disable Metrics/MethodLength
    {
      id: page.id,
      title: page.title,
      slug: page.slug,
      category: page.category,
      status: page.status,
      emoji: page.emoji,
      color: page.color,
      subtitle: page.subtitle,
      body: page.body,
      meta_title: page.meta_title,
      meta_description: page.meta_description,
      seo_keywords: page.seo_keywords,
      cta_label: page.cta_label,
      cta_url: page.cta_url,
      sections: page.sections || [],
      ab_variants: page.ab_variants || [],
      ab_results: page.ab_results,
      team_comments: page.team_comments || [],
      public_url: Cevico::PublicSite.page_url(page.slug),
      # prévia do rascunho: link secreto que mostra a página antes de publicar
      preview_url: "#{Cevico::PublicSite.base_url}/p/rascunho/#{page.preview_token}",
      # ambiente de montagem: prévia + token de RETOQUE (edição inline) —
      # só o time logado recebe este link
      builder_url: "#{Cevico::PublicSite.base_url}/p/rascunho/#{page.preview_token}?edit=#{page.edit_token}",
      updated_at: page.updated_at
    }.merge(page_stats_json(page))
  end

  def page_stats_json(page)
    {
      views_count: page.views_count,
      cta_clicks_count: page.cta_clicks_count,
      next_clicks_count: page.next_clicks_count,
      next_page_id: page.next_page_id,
      last7: last7_stats(page)
    }
  end

  # resumo dos últimos 7 dias (visitas/cliques) — alimenta os cards do admin
  def last7_stats(page)
    stats = page.daily_stats || {}
    keys = (0..6).map { |i| (Date.current - i).iso8601 }
    days = keys.filter_map { |k| stats[k] }
    {
      views: days.sum { |d| d['view'].to_i },
      cta: days.sum { |d| d['cta'].to_i },
      next: days.sum { |d| d['next'].to_i }
    }
  end
end
