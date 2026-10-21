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
#
# 🔁 item 340 (13/10): "a IA parou de responder quem manda áudio". O arquivo
# do WhatsApp sobe para o armazenamento DEPOIS que a mensagem é avisada; com a
# fila própria da IA (sempre livre) a leitura chegava antes do arquivo e o
# anexo ficava "failed" PARA SEMPRE ("não insiste") — e o Atendente, com o
# "peça uma vez só", ficava calado no 2º áudio. Agora:
#   - falha passageira (arquivo ainda subindo, rede, Gemini 429/5xx) NÃO é
#     definitiva: o MediaReadingJob tenta de novo em 3 s, 6 s e 12 s, e o
#     Atendente ainda tenta de novo antes de responder (até MAX_ATTEMPTS);
#   - meta['cevico_media'] guarda 'attempts' e 'transient' (passageira ×
#     definitiva) para a equipe ver o que houve;
#   - o modelo do Gemini é configurável e troca sozinho se o Google aposentar
#     o modelo (Crm::GeminiModels);
#   - sem transcrição, o marcador manda a IA SEMPRE responder pedindo para
#     escrever (pode pedir de novo, com outras palavras) — nunca silêncio.
class Crm::MediaReadingService # rubocop:disable Metrics/ClassLength
  MODEL = Crm::GeminiModels::DEFAULT
  MAX_BYTES = 15.megabytes
  AGENT_KEY = 'media_reading'.freeze
  KINDS = %w[audio image].freeze
  # US$ por milhão de tokens (Gemini 2.5 Flash): áudio 1,00 · imagem 0,30 · saída 2,50
  PRICE_IN = { 'audio' => 1.0, 'image' => 0.3 }.freeze
  PRICE_OUT = 2.5
  PROCESSING_TTL = 3.minutes
  # 🔁 item 340: tentativas por anexo (somando o job e o Atendente) e o
  # intervalo mínimo entre uma tentativa que falhou e a próxima
  MAX_ATTEMPTS = 6
  RETRY_AFTER = 20.seconds
  # quanto o Atendente espera a leitura dos anexos da mensagem que ele vai responder
  SETTLE_TIMEOUT = 25
  SETTLE_STEP = 2
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

  # já lido (ou não adianta tentar agora)? retry_now: o job da nova tentativa
  # (3/6/12 s) e a espera do Atendente não precisam respeitar o RETRY_AFTER
  def self.read?(attachment, retry_now: false)
    media = media_of(attachment)
    case media['status']
    when 'done' then true
    # 🔁 item 340: falha não é mais "lido para sempre" — passageira e com
    # tentativas sobrando volta a ser lida (antes: 'failed' = nunca mais)
    when 'failed' then !retriable?(attachment, retry_now: retry_now)
    when 'processing' then processing_fresh?(media)
    else false
    end
  end

  # falhou, mas vale tentar de novo?
  def self.retriable?(attachment, retry_now: false)
    media = media_of(attachment)
    return false unless media['status'] == 'failed'
    return false if media['transient'] == false || media['attempts'].to_i >= MAX_ATTEMPTS

    retry_now || stamp(media) <= RETRY_AFTER.ago.to_i
  end

  # outro processo está lendo agora (e não morreu no meio)
  def self.processing_fresh?(media)
    media['status'] == 'processing' && stamp(media) > PROCESSING_TTL.ago.to_i
  end

  # a leitura deste anexo terminou de vez (lida, pulada ou sem mais tentativas)
  def self.settled?(attachment)
    media = media_of(attachment)
    return true if %w[done skipped].include?(media['status'])
    return false if processing_fresh?(media)

    media['status'] == 'failed' && !retriable?(attachment, retry_now: true)
  end

  # 🔁 item 340: o Atendente vai responder ESTA mensagem — espera (até
  # SETTLE_TIMEOUT s, olhando a cada SETTLE_STEP s) a leitura dos áudios/imagens
  # dela terminar; o que não começou ou falhou de forma passageira ele mesmo
  # lê na hora. Limitado no tempo e nas tentativas (a trava da conversa dura 30 min).
  # Devolve os totais lidos AQUI: { 'audio' => n, 'image' => n }.
  def self.settle!(message, timeout: SETTLE_TIMEOUT, step: SETTLE_STEP) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    done = Hash.new(0)
    return done if message.blank? || !configured?(message.account)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      open = message.attachments.reload.select { |a| readable?(a) && !settled?(a) }
      break if open.empty?

      open.each do |a|
        next if processing_fresh?(media_of(a)) # outro processo está lendo: só espera

        done[a.file_type.to_s] += 1 if new(a).perform(retry_now: true)
      end
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      break if message.attachments.reload.select { |a| readable?(a) }.all? { |a| settled?(a) }

      sleep step
    end
    done
  end

  def self.media_of(attachment)
    attachment.meta&.[]('cevico_media') || {}
  end

  def self.stamp(media)
    Time.zone.parse(media['at'].to_s).to_i
  rescue StandardError
    0
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

      # 🔁 item 340: NUNCA silêncio — antes dizia "uma vez só" e o 2º áudio ficava sem resposta
      '[áudio sem transcrição: o sistema não conseguiu ouvir. RESPONDA sempre, com gentileza, pedindo para o paciente ' \
        'escrever o que precisa; se já pediu antes, peça de novo com outras palavras]'
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

  # 🔁 item 340: erros que passam sozinhos (arquivo ainda subindo para o
  # armazenamento, rede, Gemini ocupado) — vale tentar de novo
  class GeminiError < StandardError
    attr_reader :code

    def initialize(message, code)
      super(message)
      @code = code.to_i
    end

    def transient?
      code == 408 || code == 429 || code >= 500
    end
  end

  class FormatError < StandardError; end

  TRANSIENT_ERRORS = [
    ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError, FormatError,
    Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError, EOFError, OpenSSL::SSL::SSLError,
    Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH
  ].freeze

  def self.transient_error?(error)
    return error.transient? if error.is_a?(GeminiError)

    TRANSIENT_ERRORS.any? { |klass| error.is_a?(klass) } || error.class.name.to_s.include?('NoSuchKey')
  end

  # true quando leu agora; false quando pulou (já lido, sem chave, tipo errado) ou falhou
  def perform(retry_now: false) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    return false if @account.blank? || !self.class.readable?(attachment) || self.class.read?(attachment, retry_now: retry_now)
    return skip!('Configure a chave do Gemini em Integrações → IA.') if api_key.blank?
    return skip!('Arquivo acima de 15 MB.') if attachment.file.byte_size.to_i > MAX_BYTES
    return false unless claim!(retry_now)

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
    # 🔁 item 340: modelo configurável, com troca automática se o Google aposentar
    response, @model = Crm::GeminiModels.post(account: @account, api_key: api_key, body: body.to_json, timeout: 90)
    raise GeminiError.new("Gemini respondeu com erro #{response.code}: #{gemini_error(response)}", response.code) unless response.success?

    response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
  end

  def gemini_error(response)
    parsed = response.parsed_response
    (parsed.is_a?(Hash) ? parsed.dig('error', 'message') : nil).to_s.truncate(120)
  end

  def parse_json(text)
    raise FormatError, 'O Gemini não devolveu texto.' if text.blank?

    clean = text.to_s.gsub(/```(?:json)?/i, '').strip
    [clean, clean[(clean.index('{') || 0)..(clean.rindex('}') || -1)]].each do |candidate|
      parsed = JSON.parse(candidate)
      return parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      next
    end
    raise FormatError, 'O Gemini respondeu fora do formato esperado.'
  end

  def save!(parsed) # rubocop:disable Metrics/AbcSize
    fields = { 'status' => 'done', 'error' => nil, 'transient' => nil, 'model' => model_used, 'at' => Time.current.iso8601 }
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

  def model_used
    @model || MODEL
  end

  # 🔁 item 340: marca "lendo" e conta a tentativa, com a linha do anexo
  # travada — o MediaReadingJob e o Atendente nunca leem o mesmo anexo juntos
  def claim!(retry_now)
    claimed = false
    attachment.with_lock do
      next if self.class.read?(attachment, retry_now: retry_now)

      attempts = self.class.media_of(attachment)['attempts'].to_i + 1
      write!('status' => 'processing', 'error' => nil, 'attempts' => attempts, 'at' => Time.current.iso8601)
      claimed = true
    end
    claimed
  end

  def fail!(error) # rubocop:disable Metrics/AbcSize
    transient = self.class.transient_error?(error)
    Rails.logger.warn("[CEVICO mídia] leitura do anexo #{attachment.id} (#{kind}) falhou#{' (passageira)' if transient}: " \
                      "#{error.class}: #{error.message}")
    write!('status' => 'failed', 'error' => error.message.to_s.strip.truncate(180).presence || 'A leitura falhou.',
           'transient' => transient, 'error_class' => error.class.name.to_s.truncate(60), 'at' => Time.current.iso8601)
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
    Crm::AiUsage.create!(account: @account, agent_key: AGENT_KEY, model: model_used,
                         input_tokens: input, output_tokens: output, cost_usd: cost.round(6))
  rescue StandardError => e
    Rails.logger.warn("[Crm::AiUsage] falhou ao registrar a leitura de mídia: #{e.message}")
  end
end
