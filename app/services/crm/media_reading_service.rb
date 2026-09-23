# 👂🖼️ LEITURA DE ÁUDIO E IMAGEM do paciente (item 204, 22/09 noite).
# O N8N transcrevia o áudio (OpenAI) e descrevia a foto; o agente próprio só
# via "[áudio]" e pedia para escrever. Agora: todo áudio ou imagem que o
# paciente manda numa caixa atendida pelos Atendentes do WhatsApp passa pelo
# Gemini (mesmo padrão da transcrição de vídeo dos criativos) e vira TEXTO:
#   - áudio  → transcrição fiel (attachment.meta['transcribed_text'], a chave
#              que o Chatwoot já mostra embaixo do player para a equipe);
#   - imagem → o que a foto mostra + todo texto legível (receita, pedido de
#              exame, print, comprovante), sem diagnóstico.
# O detalhe fica em meta['cevico_media'] e o Atendente lê o texto na conversa
# como se o paciente tivesse escrito. Sem chave do Gemini: nada quebra, o
# agente segue pedindo para escrever (Integrações → IA).
class Crm::MediaReadingService # rubocop:disable Metrics/ClassLength
  MODEL = 'gemini-2.5-flash'.freeze
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent".freeze
  MAX_BYTES = 15.megabytes
  AGENT_KEY = 'media_reading'.freeze
  KINDS = %w[audio image].freeze
  # US$ por milhão de tokens (Gemini 2.5 Flash): áudio 1,00 · imagem 0,30 · saída 2,50
  PRICE_IN = { 'audio' => 1.0, 'image' => 0.3 }.freeze
  PRICE_OUT = 2.5
  PROCESSING_TTL = 3.minutes
  # quantos anexos por conversa cada chamada do Atendente lê no máximo (latência)
  PENDING_MESSAGES = 8
  PENDING_ATTACHMENTS = 4
  OTHER_LABELS = { 'video' => 'vídeo', 'file' => 'arquivo', 'location' => 'localização', 'contact' => 'contato' }.freeze

  AUDIO_PROMPT = <<~TXT.freeze
    Você recebe um áudio enviado por um paciente ao WhatsApp de uma clínica de oftalmologia (português do Brasil).
    Transcreva FIELMENTE tudo o que a pessoa fala, na ordem, sem resumir, sem corrigir o sentido e mantendo números,
    nomes, valores e horários como foram ditos. Se não houver fala compreensível, devolva texto vazio e inaudivel true.
    Responda SOMENTE com um JSON válido, sem comentários:
    {"texto": "...", "idioma": "pt-BR", "inaudivel": false}
  TXT

  IMAGE_PROMPT = <<~TXT.freeze
    Você recebe uma imagem enviada por um paciente ao WhatsApp de uma clínica de oftalmologia (português do Brasil).
    1) "tipo": classifique em UMA palavra: receita | pedido_exame | exame_laudo | foto_olho | print | comprovante | documento | outro.
    2) "descricao": em até 2 frases, o que a imagem mostra (sem diagnóstico, sem opinar sobre saúde).
    3) "texto": TODO o texto legível na imagem, copiado literalmente (nomes de exames, graus, médico, datas, valores,
       mensagens de um print). Vazio se não houver texto.
    Responda SOMENTE com um JSON válido, sem comentários:
    {"tipo": "...", "descricao": "...", "texto": "..."}
  TXT

  # ── uso pelo motor dos Atendentes ─────────────────────────────────────────
  def self.configured?(account)
    api_key_for(account).present?
  end

  def self.api_key_for(account)
    CrmSetting.find_by(account: account)&.ai_config&.dig('gemini_api_key').presence
  end

  # lê (se ainda não leu) os áudios/imagens das últimas mensagens do paciente
  # nesta conversa, ANTES do Atendente montar a resposta. Devolve os totais
  # lidos agora: { 'audio' => n, 'image' => n } (vazio quando não há chave).
  def self.read_pending!(conversation)
    return {} unless configured?(conversation.account)

    done = Hash.new(0)
    pending_attachments(conversation).each do |attachment|
      done[attachment.file_type.to_s] += 1 if new(attachment).perform
    end
    done
  end

  def self.pending_attachments(conversation)
    messages = conversation.messages.where(message_type: :incoming).includes(:attachments)
                           .reorder(created_at: :desc).limit(PENDING_MESSAGES)
    pending = messages.flat_map { |m| m.attachments.select { |a| readable?(a) && !read?(a) } }
    pending.sort_by(&:created_at).first(PENDING_ATTACHMENTS)
  end

  def self.readable?(attachment)
    KINDS.include?(attachment.file_type.to_s) && attachment.file.attached?
  end

  def self.read?(attachment)
    media = attachment.meta&.[]('cevico_media') || {}
    return true if media['status'] == 'done'
    return true if media['status'] == 'failed' # não insiste: custaria a cada mensagem
    return false unless media['status'] == 'processing'

    Time.zone.parse(media['at'].to_s).to_i > PROCESSING_TTL.ago.to_i
  rescue StandardError
    false
  end

  def self.message_has_media?(message)
    message.attachments.any? { |a| KINDS.include?(a.file_type.to_s) }
  end

  # o que entra na CONVERSA que o Atendente lê (uma linha por anexo)
  def self.transcript_label(attachment) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    media = attachment.meta&.[]('cevico_media') || {}
    text = attachment.meta&.[]('transcribed_text').to_s.strip
    case attachment.file_type.to_s
    when 'audio'
      return "[áudio transcrito: \"#{text.truncate(900)}\"]" if media['status'] == 'done' && text.present?
      return '[áudio sem fala compreensível: pergunte o que o paciente precisa]' if media['status'] == 'done'

      '[áudio sem transcrição: peça para o paciente escrever em uma frase, uma vez só]'
    when 'image'
      if media['status'] == 'done'
        parts = ["imagem (#{media['tipo'].presence || 'outro'}): #{media['descricao'].to_s.strip.presence || 'sem descrição'}"]
        parts << "texto na imagem: \"#{media['texto'].to_s.strip.truncate(900)}\"" if media['texto'].to_s.strip.present?
        return "[#{parts.join(' · ')}]"
      end

      '[imagem: não foi possível ler; pergunte ao paciente o que ele enviou]'
    else
      "[#{OTHER_LABELS[attachment.file_type.to_s] || attachment.file_type}]"
    end
  end

  # ── um anexo por vez ──────────────────────────────────────────────────────
  attr_reader :attachment

  def initialize(attachment)
    @attachment = attachment
    @message = attachment.message
    @account = @message&.account
  end

  # true quando leu agora; false quando pulou (já lido, sem chave, tipo errado) ou falhou
  def perform # rubocop:disable Metrics/AbcSize
    return false if @account.blank? || !self.class.readable?(attachment) || self.class.read?(attachment)
    return skip!('Configure a chave do Gemini em Integrações → IA.') if api_key.blank?
    return skip!('Arquivo acima de 15 MB.') if attachment.file.byte_size.to_i > MAX_BYTES

    mark!('processing')
    response = ask_gemini(attachment.file.blob.open(&:read), mime)
    parsed = parse_json(response.dig('candidates', 0, 'content', 'parts', 0, 'text'))
    save!(parsed)
    record_usage(response['usageMetadata'])
    true
  rescue StandardError => e
    fail!(e)
  end

  private

  def kind
    attachment.file_type.to_s
  end

  def api_key
    @api_key ||= self.class.api_key_for(@account)
  end

  def mime
    type = attachment.file.content_type.to_s
    return type if type.present? && type != 'application/octet-stream'

    kind == 'audio' ? 'audio/ogg' : 'image/jpeg'
  end

  def prompt
    return AUDIO_PROMPT if kind == 'audio'

    caption = @message.content.to_s.strip
    caption.present? ? "#{IMAGE_PROMPT}\nLegenda que o paciente escreveu junto: \"#{caption.truncate(300)}\"" : IMAGE_PROMPT
  end

  def ask_gemini(bytes, mime_type)
    body = {
      contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: mime_type, data: Base64.strict_encode64(bytes) } }] }],
      generationConfig: { temperature: 0.1, response_mime_type: 'application/json' }
    }
    response = HTTParty.post(GEMINI_URL, query: { key: api_key }, headers: { 'Content-Type' => 'application/json' },
                                         body: body.to_json, timeout: 90)
    raise "Gemini respondeu com erro #{response.code}: #{gemini_error(response)}" unless response.success?

    response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
  end

  def gemini_error(response)
    parsed = response.parsed_response
    (parsed.is_a?(Hash) ? parsed.dig('error', 'message') : nil).to_s.truncate(120)
  end

  def parse_json(text)
    raise 'O Gemini não devolveu texto.' if text.blank?

    clean = text.to_s.gsub(/```(?:json)?/i, '').strip
    [clean, clean[(clean.index('{') || 0)..(clean.rindex('}') || -1)]].each do |candidate|
      parsed = JSON.parse(candidate)
      return parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      next
    end
    raise 'O Gemini respondeu fora do formato esperado.'
  end

  def save!(parsed) # rubocop:disable Metrics/AbcSize
    fields = { 'status' => 'done', 'error' => nil, 'model' => MODEL, 'at' => Time.current.iso8601 }
    if kind == 'audio'
      text = parsed['texto'].to_s.strip.truncate(4000)
      fields['inaudivel'] = parsed['inaudivel'] == true || text.blank?
      write!(fields, text)
    else
      descricao = parsed['descricao'].to_s.strip.truncate(600)
      texto = parsed['texto'].to_s.strip.truncate(3000)
      fields.merge!('tipo' => parsed['tipo'].to_s.strip.downcase.presence || 'outro', 'descricao' => descricao, 'texto' => texto)
      summary = [descricao.presence, (texto.present? ? "Texto: #{texto}" : nil)].compact.join(' · ')
      write!(fields, summary)
    end
  end

  def skip!(reason)
    write!('status' => 'skipped', 'error' => reason)
    false
  end

  def mark!(status)
    write!('status' => status, 'error' => nil, 'at' => Time.current.iso8601)
  end

  def fail!(error)
    Rails.logger.warn("[CEVICO mídia] leitura do anexo #{attachment.id} (#{kind}) falhou: #{error.class}: #{error.message}")
    write!('status' => 'failed', 'error' => error.message.to_s.strip.truncate(180).presence || 'A leitura falhou.',
           'at' => Time.current.iso8601)
    false
  rescue StandardError => e
    Rails.logger.error("[CEVICO mídia] não deu nem para marcar a falha do anexo #{attachment.id}: #{e.message}")
    false
  end

  # grava meta['cevico_media'] (e transcribed_text quando há texto) e avisa a
  # tela da conversa, que passa a mostrar o texto embaixo do anexo
  def write!(fields, transcribed_text = nil)
    attachment.reload
    meta = (attachment.meta || {}).dup
    meta['cevico_media'] = (meta['cevico_media'] || {}).merge(fields)
    meta['transcribed_text'] = transcribed_text unless transcribed_text.nil?
    attachment.update!(meta: meta)
    @message.reload.send_update_event if transcribed_text.present?
  end

  def record_usage(usage)
    return if usage.blank?

    input = usage['promptTokenCount'].to_i
    output = usage['candidatesTokenCount'].to_i
    cost = ((input * (PRICE_IN[kind] || PRICE_IN['image'])) + (output * PRICE_OUT)) / 1_000_000.0
    Crm::AiUsage.create!(account: @account, agent_key: AGENT_KEY, model: MODEL,
                         input_tokens: input, output_tokens: output, cost_usd: cost.round(6))
  rescue StandardError => e
    Rails.logger.warn("[Crm::AiUsage] falhou ao registrar a leitura de mídia: #{e.message}")
  end
end
