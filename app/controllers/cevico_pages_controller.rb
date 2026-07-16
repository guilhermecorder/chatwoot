# Página PÚBLICA CEVICO (/p/:slug) — sem login, preparada para SEO:
# meta title/description próprios, Open Graph e URL limpa. Só páginas
# publicadas aparecem; rascunho responde 404.
class CevicoPagesController < ActionController::Base # rubocop:disable Rails/ApplicationController
  layout false

  def show
    @page = CevicoPage.published.find_by(slug: params[:slug])
    return render plain: 'Página não encontrada.', status: :not_found if @page.nil?

    # contador simples de visitas (sem cookie, sem rastreio)
    @page.increment!(:views_count) # rubocop:disable Rails/SkipsModelValidations
    render :show
  end
end
