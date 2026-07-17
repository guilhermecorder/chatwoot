# Página PÚBLICA CEVICO (/p/:slug) — sem login, preparada para SEO:
# meta title/description próprios, Open Graph e URL limpa. Só páginas
# publicadas aparecem; rascunho responde 404.
#
# Com o domínio oficial configurado (CEVICO_PUBLIC_HOST), a página também
# responde na RAIZ desse domínio (www.cevico.com.br/preoperatorio) e os
# endereços antigos redirecionam 301 pro oficial — um endereço só aos
# olhos do Google e da Meta.
class CevicoPagesController < ActionController::Base # rubocop:disable Rails/ApplicationController
  layout false

  def show
    @page = CevicoPage.published.find_by(slug: params[:slug])
    return render plain: 'Página não encontrada.', status: :not_found if @page.nil?

    # endereço antigo (/p/slug ou host da VPS) → 301 pro oficial
    if Cevico::PublicSite.configured? && request.path != "/#{@page.slug}"
      official = Cevico::PublicSite.page_url(@page.slug)
      official += "?de=#{origin_slug}" if origin_slug.present?
      return redirect_to official, status: :moved_permanently, allow_other_host: true
    end

    # teste A/B: sorteia a variação (ou respeita ?v= de quem já entrou nela)
    @page.serving_variant = requested_variant(@page) || (@page.ab_test_running? ? @page.pick_variant : nil)

    # contador simples de visitas por dia (sem cookie, sem rastreio);
    # ?de=slug marca de qual página do funil o visitante veio
    @page.track_hit!('view', source: origin_slug, variant: @page.serving_variant)
    render :show
  end

  # clique no convite (WhatsApp/cta_url): conta e manda pro destino
  def cta_click
    @page = CevicoPage.published.find_by(slug: params[:slug])
    return render plain: 'Página não encontrada.', status: :not_found if @page.nil? || @page.cta_url.blank?

    @page.track_hit!('cta', variant: requested_variant(@page))
    redirect_to @page.cta_url, allow_other_host: true
  end

  # próximo passo do funil: conta o clique e leva pra próxima página
  # CEVICO, marcando a origem (?de=) pra medir a conversão do caminho
  def next_step
    @page = CevicoPage.published.find_by(slug: params[:slug])
    target = @page&.funnel_target
    return render plain: 'Página não encontrada.', status: :not_found if @page.nil? || target.nil?

    @page.track_hit!('next', variant: requested_variant(@page))
    redirect_to "#{Cevico::PublicSite.page_url(target.slug)}?de=#{@page.slug}",
                allow_other_host: true
  end

  # beacon de profundidade de rolagem (25/50/75/100) — enviado uma vez
  # por visita pelo sendBeacon; alimenta o "quanto da página leram"
  skip_forgery_protection only: :track

  def track
    page = CevicoPage.published.find_by(slug: params[:slug])
    return head :not_found if page.nil?

    page.track_scroll!(params[:depth])
    head :no_content
  end

  # Raiz do domínio oficial: índice enxuto das páginas publicadas,
  # agrupado pelas categorias da jornada.
  def home
    @pages_by_category = CevicoPage.published
                                   .order(:title)
                                   .group_by(&:category)
    render :home
  end

  private

  # slug da página de origem do funil (?de=...), saneado
  def origin_slug
    params[:de].to_s.gsub(/[^a-z0-9-]/, '')[0, 60].presence
  end

  # variação pedida no ?v= — só vale se for uma variação REAL da página
  def requested_variant(page)
    v = params[:v].to_s.gsub(/[^a-z0-9]/, '')[0, 3].presence
    return nil if v.blank? || page.nil?
    return v if v == 'a' || page.active_variants.any? { |var| var['key'] == v }

    nil
  end
end
