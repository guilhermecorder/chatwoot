# 🎬 item 292 (29/09, produção: "A Meta não devolveu o arquivo do vídeo"): de
# onde baixar o vídeo de um anúncio. O arquivo pertence à PÁGINA que publicou;
# o acesso da conta de anúncios nem sempre basta. Três caminhos, do mais
# simples ao mais completo:
#   1) o vídeo direto, com o acesso configurado em Integrações → Meta Ads;
#   2) a biblioteca de vídeos da conta de anúncios;
#   3) o vídeo com o acesso da página dona do anúncio.
# Se nenhum entregar, o erro diz em português o que falta liberar e guarda, em
# `detail`, o que a Meta respondeu em cada caminho.
class Crm::AdVideoSource
  class Missing < StandardError
    attr_reader :detail

    def initialize(message, detail)
      super(message)
      @detail = detail
    end
  end

  def initialize(creative, graph)
    @creative = creative
    @graph = graph
    @tried = []
  end

  def url
    found = direct_url || library_url || page_url
    return found if found.present?

    Rails.logger.warn("[CEVICO criativos] vídeo #{video_id} do anúncio #{@creative.ad_id} sem arquivo — #{@tried.join(' | ')}")
    raise Missing.new(message, @tried.join(' | '))
  end

  private

  def video_id
    @creative.creative['video_id'].to_s
  end

  def direct_url
    obj, error = @graph.fetch_one(video_id, 'source,length')
    tried('vídeo direto', error)
    obj&.dig('source').presence
  end

  def library_url
    filter = [{ field: 'id', operator: 'IN', value: [video_id] }].to_json
    rows = @graph.fetch_all('advideos', { fields: 'id,source', filtering: filter, limit: 5 }, max_pages: 1)
    tried('biblioteca da conta', nil)
    rows.find { |row| row['id'].to_s == video_id }&.dig('source').presence
  rescue StandardError => e
    tried('biblioteca da conta', e.message)
    nil
  end

  def page_url
    token = @graph.page_token(page_id)
    if token.blank?
      tried('página', page_id.present? ? "o acesso não enxerga a página #{page_id}" : 'anúncio sem página identificada')
      return nil
    end

    obj, error = @graph.fetch_one(video_id, 'source,length', token: token)
    tried('página', error)
    obj&.dig('source').presence
  end

  # página dona do anúncio (object_story_spec.page_id; senão quem publicou)
  def page_id
    @page_id ||= begin
      ad, = @graph.fetch_one(@creative.ad_id, 'creative{actor_id,object_story_spec,effective_object_story_id}')
      data = ad&.dig('creative') || {}
      (data.dig('object_story_spec', 'page_id') || data['effective_object_story_id'].to_s.split('_').first.presence ||
        data['actor_id']).to_s
    end
  end

  def tried(path, error)
    @tried << "#{path}: #{error.presence || 'sem o arquivo'}"
  end

  def message
    page = page_id.present? ? " (página #{page_id})" : ''
    "A Meta não liberou o arquivo do vídeo: o acesso da Meta precisa enxergar a página que publicou o anúncio#{page}."
  end
end
