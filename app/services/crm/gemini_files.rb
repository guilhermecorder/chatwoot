# 🎬 item 293: vídeo grande (acima de 18 MB) não cabe embutido no pedido ao
# Gemini — sobe antes pela "gaveta de arquivos" do Gemini (Files API), espera
# ficar pronto e devolve o endereço para usar no pedido. O Gemini apaga o
# arquivo sozinho depois de 48 horas.
class Crm::GeminiFiles
  UPLOAD_URL = 'https://generativelanguage.googleapis.com/upload/v1beta/files'.freeze
  BASE_URL = 'https://generativelanguage.googleapis.com/v1beta'.freeze
  READY_TRIES = 40
  READY_WAIT = 3

  def initialize(api_key)
    @api_key = api_key
  end

  # envia os bytes e devolve o endereço (file_uri) já pronto para uso
  def upload(bytes, mime)
    file = finish(start(bytes.bytesize, mime), bytes)
    raise 'O Gemini não devolveu o endereço do vídeo enviado.' if file['uri'].blank?

    wait_ready(file)
  end

  private

  def start(size, mime)
    response = HTTParty.post(UPLOAD_URL, query: { key: @api_key }, timeout: 60,
                                         headers: { 'X-Goog-Upload-Protocol' => 'resumable', 'X-Goog-Upload-Command' => 'start',
                                                    'X-Goog-Upload-Header-Content-Length' => size.to_s,
                                                    'X-Goog-Upload-Header-Content-Type' => mime, 'Content-Type' => 'application/json' },
                                         body: { file: { display_name: "anuncio-#{Time.current.to_i}" } }.to_json)
    url = response.headers['x-goog-upload-url'].to_s
    raise "O Gemini recusou o envio do vídeo (erro #{response.code})." unless response.success? && url.present?

    url
  end

  def finish(url, bytes)
    response = HTTParty.post(url, timeout: 600, body: bytes,
                                  headers: { 'Content-Length' => bytes.bytesize.to_s, 'X-Goog-Upload-Offset' => '0',
                                             'X-Goog-Upload-Command' => 'upload, finalize' })
    raise "O envio do vídeo ao Gemini falhou (erro #{response.code})." unless response.success?

    (response.parsed_response.is_a?(Hash) ? response.parsed_response['file'] : nil) || {}
  end

  # vídeo passa por um preparo do lado do Gemini antes de poder ser usado
  def wait_ready(file)
    READY_TRIES.times do
      return file['uri'] if file['state'].to_s == 'ACTIVE'
      raise 'O Gemini não conseguiu preparar este vídeo.' if file['state'].to_s == 'FAILED'

      sleep READY_WAIT
      file = HTTParty.get("#{BASE_URL}/#{file['name']}", query: { key: @api_key }, timeout: 30).parsed_response || {}
    end
    raise 'O Gemini demorou demais para preparar o vídeo. Tente de novo em alguns minutos.'
  end
end
