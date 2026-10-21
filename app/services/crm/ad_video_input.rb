# 🎬 item 293 (29/09, ideia dele: "soltar o link, ler o link e transcrever o
# vídeo"): o vídeo de um anúncio pode chegar por 3 portas, nesta ordem:
#   1) ARQUIVO enviado pela pessoa na tela do anúncio (fica guardado só até transcrever);
#   2) LINK colado: YouTube (o Gemini assiste direto) ou link direto de arquivo de vídeo;
#   3) a própria META (Crm::AdVideoSource) — o caminho automático.
# Devolve um "pedaço" pronto para o Gemini: vídeo pequeno vai embutido; vídeo
# grande (ou YouTube) vai por endereço.
# Link de post do Instagram/Facebook NÃO funciona: a Meta não entrega o arquivo por fora.
class Crm::AdVideoInput
  INLINE_MAX = 18.megabytes
  UPLOAD_MAX = 200.megabytes
  YOUTUBE = %r{\Ahttps://(www\.|m\.)?(youtube\.com/(watch\?|shorts/)|youtu\.be/)}i
  SOCIAL = %r{\Ahttps?://([a-z0-9-]+\.)*(instagram\.com|facebook\.com|fb\.watch|fb\.com)/}i
  SOCIAL_MESSAGE = 'Link do Instagram ou Facebook não pode ser lido por fora. Baixe o vídeo e solte o arquivo aqui.'.freeze

  def self.link_problem(link)
    url = link.to_s.strip
    return 'Cole um link que comece com https://' unless url.start_with?('https://')
    return SOCIAL_MESSAGE if url.match?(SOCIAL)

    nil
  end

  def initialize(creative, graph:, gemini:)
    @creative = creative
    @graph = graph
    @gemini = gemini
  end

  # de onde veio: 'upload' | 'link' | 'meta'
  def origin
    return 'upload' if @creative.video_upload.attached?
    return 'link' if link.present?

    'meta'
  end

  # pedaço do pedido ao Gemini com o vídeo
  def part
    case origin
    when 'upload' then part_for(@creative.video_upload.download, @creative.video_upload.content_type)
    when 'link' then link_part
    else meta_part
    end
  end

  # terminou: o arquivo enviado não precisa mais ocupar espaço
  def cleanup!
    @creative.video_upload.purge if @creative.video_upload.attached?
  rescue StandardError => e
    Rails.logger.warn("[CEVICO criativos] não consegui apagar o vídeo enviado: #{e.message}")
  end

  private

  def link
    @creative.transcript['link'].to_s.strip
  end

  def link_part
    problem = self.class.link_problem(link)
    raise problem if problem
    return { file_data: { mime_type: 'video/*', file_uri: link } } if link.match?(YOUTUBE)

    SafeFetch.fetch(link, max_bytes: UPLOAD_MAX, read_timeout: 180, allowed_content_type_prefixes: %w[video/]) do |result|
      return part_for(result.tempfile.read, result.content_type)
    end
  rescue SafeFetch::UnsupportedContentTypeError
    raise 'Este link não entrega um arquivo de vídeo (abre uma página). Baixe o vídeo e solte o arquivo aqui.'
  rescue SafeFetch::FileTooLargeError
    raise 'Vídeo do link acima de 200 MB.'
  rescue SafeFetch::Error => e
    raise "Não consegui baixar o vídeo do link: #{e.message.to_s.truncate(80)}"
  end

  def meta_part
    url = Crm::AdVideoSource.new(@creative, @graph).url
    file = Down.download(url, max_size: UPLOAD_MAX, open_timeout: 20, read_timeout: 180)
    part_for(file.read, file.respond_to?(:content_type) ? file.content_type : nil)
  rescue Down::TooLarge
    raise 'Vídeo acima de 200 MB — grande demais para transcrever.'
  ensure
    file&.close! if file.respond_to?(:close!)
  end

  def part_for(bytes, mime)
    mime = mime.to_s.presence || 'video/mp4'
    raise 'O arquivo veio vazio.' if bytes.blank?
    return { inline_data: { mime_type: mime, data: Base64.strict_encode64(bytes) } } if bytes.bytesize <= INLINE_MAX

    { file_data: { mime_type: mime, file_uri: @gemini.upload(bytes, mime) } }
  end
end
