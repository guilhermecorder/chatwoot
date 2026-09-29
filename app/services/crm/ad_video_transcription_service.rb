# 🎬 TRANSCRIÇÃO DO VÍDEO do anúncio (Central de Criativos v2.1, item 181):
# o que importa para a clínica é o que o vídeo FALA, não o texto do anúncio.
# Baixa o vídeo pela Graph API (`GET /{video_id}?fields=source`), manda ao
# Gemini (vídeo inline, até 18 MB) e guarda em `creative['transcript']`:
#   { text, hook, body, cta, angle, language, status, error, transcribed_at,
#     duration_hint, model }
# Gancho = o que é dito nos primeiros ~3 s (o que segura); corpo = o
# desenvolvimento; CTA = o pedido final. Simulação (token 'simulate') gera
# um texto fictício sem chamar a Meta nem o Gemini. Nunca levanta erro:
# falha vira status 'failed' com motivo curto em português.
class Crm::AdVideoTranscriptionService
  MODEL = 'gemini-2.5-flash'.freeze
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent".freeze
  MAX_BYTES = 18.megabytes
  AGENT_KEY = 'creatives_video_transcription'.freeze
  PRICE_IN = 1.0
  PRICE_OUT = 2.5
  # item 286: falta de chave é passageira — quando a chave chegar, tenta de novo sozinho
  NO_KEY = 'Configure a chave do Gemini em Integrações → IA'.freeze
  PROMPT = <<~TXT.freeze
    Você recebe o vídeo de um anúncio de uma clínica de oftalmologia (português do Brasil).
    1) Transcreva TUDO o que é falado (e o texto na tela, se for o único conteúdo), na ordem.
    2) Separe a fala em três partes, copiando o texto literal:
       - "gancho": o que é dito nos primeiros 3 segundos (a primeira frase que prende a atenção);
       - "corpo": o desenvolvimento (argumento, prova, explicação);
       - "cta": o pedido final (o que a pessoa deve fazer: chamar no WhatsApp, agendar, clicar…).
    3) Classifique o "angulo" do gancho em UMA palavra: pergunta | dor | curiosidade | prova | oferta | autoridade | historia | outro.
    4) Marque o TEMPO da fala em "trechos": a transcrição inteira dividida em frases curtas, na ordem, cada uma com o
       segundo em que começa ("inicio") e o segundo em que termina ("fim"), contados desde o começo do vídeo
       (números, podem ter uma casa decimal). Informe também "duracao": quantos segundos o vídeo dura.
    Responda SOMENTE com um JSON válido, sem comentários:
    {"transcricao": "...", "gancho": "...", "corpo": "...", "cta": "...", "angulo": "...", "idioma": "pt-BR",
     "duracao": 0, "trechos": [{"inicio": 0, "fim": 0, "texto": "..."}]}
  TXT

  attr_reader :creative

  def initialize(creative)
    @creative = creative
    @account = creative.account
  end

  def perform
    reason = precheck
    return skip!(reason, retry_later: reason == NO_KEY) if reason

    mark!('processing')
    return save!(simulated_result) if graph.simulate? && !creative.manual_video?

    transcribe_with_gemini
  rescue StandardError => e
    fail!(e)
  end

  private

  def precheck # rubocop:disable Metrics/CyclomaticComplexity
    return 'Só vídeos têm transcrição.' unless creative.transcribable? || creative.manual_video?
    return 'Este anúncio não tem vídeo identificado na Meta.' if video_id.blank? && !creative.manual_video? && !graph.simulate?
    return NO_KEY if api_key.blank? && !graph.simulate?

    nil
  end

  def transcribe_with_gemini
    response = ask_gemini(input.part)
    save!(parse_json(response.dig('candidates', 0, 'content', 'parts', 0, 'text')).merge('origem' => input.origin))
    record_usage(response['usageMetadata'])
    input.cleanup!
    true
  end

  # item 293: arquivo enviado → link colado → Meta (Crm::AdVideoInput)
  def input
    @input ||= Crm::AdVideoInput.new(creative, graph: graph, gemini: Crm::GeminiFiles.new(api_key))
  end

  def graph
    @graph ||= Crm::MetaGraph.new(account: @account)
  end

  def video_id
    creative.creative['video_id'].to_s
  end

  def api_key
    @api_key ||= CrmSetting.find_by(account: @account)&.ai_config&.dig('gemini_api_key')
  end

  def ask_gemini(video_part)
    body = {
      contents: [{ parts: [{ text: PROMPT }, video_part] }],
      generationConfig: { temperature: 0.1, response_mime_type: 'application/json' }
    }
    response = HTTParty.post(GEMINI_URL, query: { key: api_key }, headers: { 'Content-Type' => 'application/json' },
                                         body: body.to_json, timeout: 240)
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

  def save!(parsed)
    text = parsed['transcricao'].to_s.strip
    raise 'O Gemini não conseguiu transcrever o vídeo.' if text.blank?

    write_transcript(transcript_fields(parsed, text))
    true
  end

  def transcript_fields(parsed, text) # rubocop:disable Metrics/AbcSize
    part = ->(key, max) { parsed[key].to_s.strip.truncate(max).presence }
    { 'status' => 'done', 'error' => nil, 'text' => text.truncate(6000),
      'hook' => part.call('gancho', 400), 'body' => part.call('corpo', 3000), 'cta' => part.call('cta', 400),
      'angle' => parsed['angulo'].to_s.strip.downcase.presence, 'language' => parsed['idioma'].to_s.presence || 'pt-BR',
      'transcribed_at' => Time.current.iso8601, 'model' => MODEL,
      # item 287 (opcionais): tempo de cada trecho falado e duração do vídeo
      'segments' => segments_from(parsed['trechos']), 'duration' => parsed['duracao'].to_f.positive? ? parsed['duracao'].to_f.round(1) : nil }
  end

  # [{ "inicio", "fim", "texto" }] → [{ 'start', 'end', 'text' }]; o que vier torto é ignorado
  def segments_from(list)
    rows = Array(list).filter_map do |row|
      next unless row.is_a?(Hash) && row['texto'].to_s.strip.present?

      start = row['inicio'].to_f.clamp(0, 3600)
      { 'start' => start.round(1), 'end' => [row['fim'].to_f, start].max.clamp(0, 3600).round(1), 'text' => row['texto'].to_s.strip.truncate(600) }
    end
    rows.sort_by { |row| row['start'] }.first(200).presence
  end

  # simulação local: texto coerente com o nome do anúncio, sem Meta nem Gemini
  def simulated_result
    name = creative.ad_name.to_s
    hook = name[/"([^"]+)"/, 1] || 'Você ainda depende dos óculos para tudo?'
    { 'transcricao' => "#{hook} Na CEVICO a gente avalia o seu caso com tecnologia de ponta e te explica cada passo. " \
                       'Chama a gente no WhatsApp e agende a sua avaliação.',
      'gancho' => hook, 'corpo' => 'Na CEVICO a gente avalia o seu caso com tecnologia de ponta e te explica cada passo.',
      'cta' => 'Chama a gente no WhatsApp e agende a sua avaliação.', 'angulo' => hook.include?('?') ? 'pergunta' : 'prova',
      'idioma' => 'pt-BR' }.merge(simulated_timing(hook))
  end

  # item 287: tempo fictício dos trechos, coerente com a duração simulada do vídeo
  def simulated_timing(hook)
    length = Crm::MetaSimulator.video_length(creative.ad_id).to_f
    { 'duracao' => length,
      'trechos' => [{ 'inicio' => 0, 'fim' => 3, 'texto' => hook },
                    { 'inicio' => 3, 'fim' => (length * 0.75).round(1),
                      'texto' => 'Na CEVICO a gente avalia o seu caso com tecnologia de ponta e te explica cada passo.' },
                    { 'inicio' => (length * 0.75).round(1), 'fim' => length,
                      'texto' => 'Chama a gente no WhatsApp e agende a sua avaliação.' }] }
  end

  def skip!(reason, retry_later: false)
    write_transcript('status' => 'skipped', 'error' => reason, 'retry' => retry_later || nil, 'status_at' => Time.current.iso8601)
    false
  end

  def mark!(status)
    write_transcript('status' => status, 'error' => nil, 'error_detail' => nil, 'retry' => nil, 'status_at' => Time.current.iso8601)
  end

  def fail!(error)
    Rails.logger.warn("[CEVICO criativos] transcrição do vídeo #{creative.ad_id} falhou: #{error.class}: #{error.message}")
    write_transcript('status' => 'failed', 'status_at' => Time.current.iso8601,
                     'error' => error.message.to_s.strip.truncate(180).presence || 'A transcrição falhou.',
                     'error_detail' => error.respond_to?(:detail) ? error.detail.to_s.truncate(600) : nil)
    false
  rescue StandardError => e
    Rails.logger.error("[CEVICO criativos] não deu nem para marcar a falha do vídeo #{creative.ad_id}: #{e.message}")
    false
  end

  # grava só a chave transcript (a carga da Meta preserva essa chave — ver AdInsightsSyncService)
  def write_transcript(fields)
    current = (creative.reload.creative['transcript'] || {}).merge(fields)
    creative.update!(creative: creative.creative.merge('transcript' => current))
  end

  def record_usage(usage)
    return if usage.blank?

    input = usage['promptTokenCount'].to_i
    output = usage['candidatesTokenCount'].to_i
    cost = ((input * PRICE_IN) + (output * PRICE_OUT)) / 1_000_000.0
    Crm::AiUsage.create!(account: @account, agent_key: AGENT_KEY, model: MODEL,
                         input_tokens: input, output_tokens: output, cost_usd: cost.round(6))
  rescue StandardError => e
    Rails.logger.warn("[Crm::AiUsage] falhou ao registrar a transcrição do vídeo: #{e.message}")
  end
end
