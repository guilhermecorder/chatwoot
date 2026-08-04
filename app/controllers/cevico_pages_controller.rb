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

  def show # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
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
    # rastreio de ORIGEM (plano 100+ páginas): visita entra no balde
    # página/dia/origem/campanha — Google Ads, SEO, Meta, funil, direto
    trk = Cevico::TrafficSource.classify(request.query_parameters, referer: request.referer)
    CevicoPageTraffic.bump!(page: @page, kind: 'view', source: trk[:source], campaign: trk[:campaign])
    return render_custom_page if @page.custom_html.present?

    render :show
  end

  # Prévia do RASCUNHO — aberta pelo link secreto gerado no admin: mostra
  # a página como o paciente veria (tarja no topo), sem contar visita,
  # sem A/B e sem contadores de clique. Com o token de RETOQUE (?edit=) e
  # página não publicada, vira o AMBIENTE DE MONTAGEM: ampulheta enquanto
  # a IA constrói, cascata de "pronta" e edição inline dos textos.
  def preview # rubocop:disable Metrics/AbcSize
    @page = CevicoPage.find_by_preview_token(params[:token])
    return render plain: 'Prévia não encontrada.', status: :not_found if @page.nil?

    @preview = true
    @can_edit = @page.valid_edit_token?(params[:edit]) && !@page.published?
    @build_status = Crm::PageGenerateJob.page_status(@page.id)
    @building = @build_status&.dig('status') == 'running'
    @build_error = @build_status&.dig('status') == 'error' ? @build_status['error'] : nil
    @just_built = params[:pronta].present?
    @page.serving_variant = nil
    # página HTML anexada: prévia serve o arquivo como veio, só com a tarja
    # de rascunho por cima (retoque inline/chat são do Construtor)
    return render_custom_page(preview_banner: render_to_string(partial: 'cevico_pages/draft_banner')) if @page.custom_html.present?

    render :show
  end

  # a aba de montagem consulta aqui até a IA terminar
  def build_status
    page = CevicoPage.find_by_preview_token(params[:token])
    return render json: { status: 'not_found' }, status: :not_found if page.nil?

    render json: Crm::PageGenerateJob.page_status(page.id) || { status: 'idle' }
  end

  # CHAT DO CONSTRUTOR (item 112): manda a instrução pro agente de
  # correção — roda em segundo plano e a aba acompanha pelo status.
  # Fase 2: aceita FOTOS anexadas (caminhos já subidos em builder_upload) —
  # o agente VÊ cada foto e a posiciona na seção onde ela comunica melhor.
  def builder_chat # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    page = CevicoPage.find_by_preview_token(params[:token])
    return head :not_found if page.nil?
    return head :forbidden unless page.valid_edit_token?(params[:edit]) && !page.published?

    images = Array(params[:images]).map(&:to_s).select { |u| u.start_with?('/rails/active_storage/') }.first(3)
    message = params[:message].to_s.strip[0, 2000]
    message = 'Posicione a(s) foto(s) anexada(s) nas seções onde elas comunicam melhor.' if message.blank? && images.any?
    return render json: { error: 'Escreva o que você quer mudar.' }, status: :unprocessable_entity if message.blank?

    Redis::Alfred.setex(Crm::PageGenerateJob.page_key(page.id), { status: 'running' }.to_json, 15.minutes)
    Crm::PageEditJob.perform_later(page.account_id, page.id, message, images)
    render json: { ok: true }
  end

  # FOTO DO CHAT (112 Fase 2): sobe a imagem pro storage e devolve o
  # caminho relativo — mesma validação do upload do editor de Páginas.
  # Exige os dois tokens (prévia + retoque) e página em rascunho.
  def builder_upload # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    page = CevicoPage.find_by_preview_token(params[:token])
    return head :not_found if page.nil?
    return head :forbidden unless page.valid_edit_token?(params[:edit]) && !page.published?

    file = params[:image]
    return render json: { error: 'Envie uma imagem.' }, status: :unprocessable_entity if file.blank? || !file.respond_to?(:content_type)
    return render json: { error: 'Só imagens (JPG, PNG, WebP).' }, status: :unprocessable_entity unless file.content_type.to_s.start_with?('image/')
    return render json: { error: 'Imagem muito grande (máx. 8 MB).' }, status: :unprocessable_entity if file.size > 8.megabytes

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.tempfile, filename: file.original_filename, content_type: file.content_type
    )
    render json: { url: Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true) }
  end

  # retoque inline (só textos; exige o token de RETOQUE e rascunho)
  def inline_update
    page = CevicoPage.find_by_preview_token(params[:token])
    return head :not_found if page.nil?
    return head :forbidden unless page.valid_edit_token?(params[:edit]) && !page.published?

    # payload livre (títulos/textos por índice) — o modelo valida campo a
    # campo com limite de tamanho; permit! só destrava a conversão
    edits = params[:edits].respond_to?(:permit!) ? params[:edits].permit!.to_h : {}
    page.apply_inline_edits!(edits)
    render json: { ok: true, saved_at: Time.zone.now.strftime('%H:%M') }
  rescue StandardError => e
    Rails.logger.error "[CevicoPages#inline_update] #{e.class}: #{e.message}"
    render json: { error: 'Não consegui salvar — tente de novo.' }, status: :unprocessable_entity
  end

  # clique no convite (WhatsApp/cta_url): conta, carimba a origem e — se o
  # destino é WhatsApp — gera o PROTOCOLO que liga o paciente à página/anúncio
  def cta_click
    @page = CevicoPage.published.find_by(slug: params[:slug])
    return render plain: 'Página não encontrada.', status: :not_found if @page.nil? || @page.cta_url.blank?

    @page.track_hit!('cta', variant: requested_variant(@page))
    trk = Cevico::TrafficSource.classify(request.query_parameters, referer: request.referer)
    CevicoPageTraffic.bump!(page: @page, kind: 'cta', source: trk[:source], campaign: trk[:campaign])
    redirect_to url_with_protocol(@page) || @page.cta_url, allow_other_host: true
  end

  # PROTOCOLO sob demanda (páginas HTML anexadas): o script da página pede
  # o código no clique do botão de WhatsApp e o injeta no texto da mensagem
  def mint_ref
    page = CevicoPage.published.find_by(slug: params[:slug])
    return head :not_found if page.nil?

    trk = Cevico::TrafficSource.classify(params, referer: request.referer)
    CevicoPageTraffic.bump!(page: page, kind: 'cta', source: trk[:source], campaign: trk[:campaign])
    page.track_hit!('cta')
    ref = CevicoPageRef.mint!(page: page, source_data: Cevico::TrafficSource.snapshot(params, page: page))
    return render json: { token: nil } if ref.nil?

    render json: { token: ref.token, line: "Protocolo: #{ref.token}" }
  end

  # próximo passo do funil: conta o clique e leva pra próxima página
  # CEVICO, marcando a origem (?de=) pra medir a conversão do caminho
  def next_step
    @page = CevicoPage.published.find_by(slug: params[:slug])
    target = @page&.funnel_target
    return render plain: 'Página não encontrada.', status: :not_found if @page.nil? || target.nil?

    @page.track_hit!('next', variant: requested_variant(@page))
    # a origem (utm/gclid/ref_host) viaja junto pro próximo passo do funil —
    # senão o Google Ads viraria "funil" na segunda página
    redirect_to "#{Cevico::PublicSite.page_url(target.slug)}?de=#{@page.slug}#{tracking_query_suffix}",
                allow_other_host: true
  end

  # beacon de rolagem + retoque inline + chat do construtor: sem
  # formulário Rails, a proteção de forgery não se aplica (a segurança é
  # o token assinado)
  skip_forgery_protection only: [:track, :inline_update, :builder_chat, :builder_upload, :mint_ref, :hub_ref]

  def track
    page = CevicoPage.published.find_by(slug: params[:slug])
    return head :not_found if page.nil?

    page.track_scroll!(params[:depth])
    head :no_content
  end

  # Raiz do domínio oficial: o HUB — porta de entrada do atendimento.
  # Três caminhos em destaque (Refrativa | Catarata | Lente Trifocal),
  # botão de WhatsApp com Protocolo e o índice das demais páginas.
  def home
    @pages_by_category = CevicoPage.published
                                   .order(:title)
                                   .group_by(&:category)
    @hub = Cevico::PublicSite.hub_config
    @hub_whatsapp = Cevico::PublicSite.hub_whatsapp_url
    @doors = hub_doors
    render :home
  end

  # Protocolo do HUB: clique no WhatsApp da porta de entrada — liga o
  # paciente da caixa à origem (Google Ads/SEO/Meta) mesmo sem página
  def hub_ref
    account = CevicoPage.published.order(:id).first&.account || Account.first
    return head :not_found if account.nil?

    ref = CevicoPageRef.mint!(page: nil, account: account,
                              source_data: Cevico::TrafficSource.snapshot(params, page: nil))
    return render json: { token: nil } if ref.nil?

    render json: { token: ref.token, line: "Protocolo: #{ref.token}" }
  end

  private

  WHATSAPP_URL = %r{\A(https?://(wa\.me|api\.whatsapp\.com)|whatsapp:)}i
  TRACKING_PARAMS = %w[utm_source utm_medium utm_campaign utm_content utm_term gclid fbclid ref_host].freeze

  # destino WhatsApp → gera o Protocolo e o anexa ao texto pré-preenchido;
  # qualquer falha = redireciona pro cta_url original (clique nunca quebra)
  def url_with_protocol(page) # rubocop:disable Metrics/AbcSize
    return nil unless page.cta_url.to_s.match?(WHATSAPP_URL)

    ref = CevicoPageRef.mint!(page: page, source_data: Cevico::TrafficSource.snapshot(request.query_parameters, page: page))
    return nil if ref.nil?

    uri = URI.parse(page.cta_url)
    query = URI.decode_www_form(uri.query.to_s).to_h
    base_text = query['text'].presence || "Olá! Estava lendo a página \"#{page.title}\" e quero saber mais."
    query['text'] = "#{base_text}\nProtocolo: #{ref.token}"
    uri.query = URI.encode_www_form(query)
    uri.to_s
  rescue StandardError => e
    Rails.logger.error "[CevicoPages#cta] protocolo falhou: #{e.message}"
    nil
  end

  # &utm_...&gclid=... presentes na URL atual, prontos pra viajar no funil
  def tracking_query_suffix
    kept = request.query_parameters.slice(*TRACKING_PARAMS).compact_blank
    kept.blank? ? '' : "&#{kept.to_query}"
  end

  # página HTML ANEXADA (feita fora do Construtor): serve como veio, com o
  # script de rastreio injetado antes do </body> (origem + protocolo) e o
  # Google Tag Manager NOS LUGARES que o Google pede (script no <head>,
  # noscript logo após o <body>) — é o que o "Testar" do GTM confere
  def render_custom_page(preview_banner: nil)
    html = @page.custom_html.to_s
    if preview_banner.nil? # ao vivo: injeta o rastreio; prévia fica limpa
      html = Cevico::Gtm.inject(html)
      snippet = render_to_string(partial: 'cevico_pages/analytics_snippet', locals: { page: @page, include_gtm: false }) +
                render_to_string(partial: 'cevico_pages/tracking_snippet', locals: { page: @page })
      html = html.match?(%r{</body>}i) ? html.sub(%r{</body>}i) { "#{snippet}</body>" } : html + snippet
    end
    render html: "#{preview_banner}#{html}".html_safe, layout: false # rubocop:disable Rails/OutputSafety
  end

  # As 3 portas padrão do hub. Cada porta procura uma página PUBLICADA
  # que fale do assunto (pelo slug/título); sem página ainda, a porta
  # manda direto pro WhatsApp com o assunto no texto — a entrada nunca
  # fica sem destino.
  HUB_DOORS = [
    { emoji: '👓', title: 'Cirurgia Refrativa', text: 'Liberdade dos óculos: miopia, astigmatismo e hipermetropia.',
      match: /refrativa|lasik|prk|miopia/i, whats: 'Olá! Quero saber mais sobre a cirurgia refrativa.' },
    { emoji: '👁️', title: 'Cirurgia de Catarata', text: 'A visão nítida de volta, com a lente certa pra sua vida.',
      match: /catarata/i, whats: 'Olá! Quero saber mais sobre a cirurgia de catarata.' },
    { emoji: '✨', title: 'Lente Trifocal', text: 'Longe, meio e perto — enxergar sem óculos depois da catarata.',
      match: /trifocal|galaxy|premium/i, whats: 'Olá! Quero saber mais sobre a lente trifocal.' }
  ].freeze

  def hub_doors
    published = CevicoPage.published.to_a
    HUB_DOORS.map do |door|
      page = published.find { |pg| pg.slug.match?(door[:match]) || pg.title.match?(door[:match]) }
      door.merge(page_slug: page&.slug)
    end
  end

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
