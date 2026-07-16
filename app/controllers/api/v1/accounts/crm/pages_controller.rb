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
                              :body, :meta_title, :meta_description, :cta_label, :cta_url,
                              sections: [:type, :effect, :title, :text, { items: [:title, :text] }])
    # só tipos/efeitos conhecidos entram no banco (a página pública confia)
    if permitted[:sections]
      permitted[:sections] = permitted[:sections].select { |sec| CevicoPage::SECTION_TYPES.include?(sec[:type]) }
      permitted[:sections].each do |sec|
        sec[:effect] = 'nenhum' unless CevicoPage::SECTION_EFFECTS.include?(sec[:effect])
      end
    end
    # quem não é admin não muda status: cria como rascunho e nunca
    # publica/despublica (o default da coluna já é draft)
    permitted.delete(:status) unless Current.account_user.administrator?
    permitted
  end

  def page_json(page)
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
      cta_label: page.cta_label,
      cta_url: page.cta_url,
      sections: page.sections || [],
      views_count: page.views_count,
      public_url: "#{ENV.fetch('FRONTEND_URL', '')}/p/#{page.slug}",
      updated_at: page.updated_at
    }
  end
end
