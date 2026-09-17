require 'open3'

# Transcreve a gravação da ligação com o Gemini (áudio inline) e guarda
# transcrição + resumo + próximo passo na ligação e no card da conversa.
# Nunca levanta erro para fora: qualquer falha vira transcript_status
# 'failed' com um motivo curto em português.
class Crm::Calls::TranscriptionService
  MODEL = 'gemini-2.5-flash'.freeze
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent".freeze
  MAX_BYTES = 18.megabytes
  AGENT_KEY = 'calls_transcription'.freeze
  # US$ por milhão de tokens (entrada de áudio / saída) — estimativa p/ o painel de uso
  PRICE_IN = 1.0
  PRICE_OUT = 2.5
  PROMPT = <<~TXT.freeze
    Você recebe o áudio de uma ligação telefônica, em português do Brasil, entre a atendente de uma clínica
    e um paciente. Transcreva a conversa identificando quem fala como "Atendente:" e "Paciente:" (uma fala
    por linha). Depois resuma em 2 frases e diga o próximo passo combinado (ou "nenhum").
    Responda SOMENTE com um JSON válido, sem comentários, neste formato:
    {"transcricao": "Atendente: ...\\nPaciente: ...", "resumo": "...", "proximo_passo": "..."}
  TXT

  attr_reader :call

  def initialize(call)
    @call = call
  end

  def perform
    return skip!('Sem gravação para transcrever.') unless call.recording.attached?
    return skip!('Configure a chave do Gemini em Integrações → IA') if api_key.blank?
    return skip!('Gravação acima de 18 MB — grande demais para transcrever.') if call.recording.byte_size.to_i > MAX_BYTES

    call.update!(transcript_status: 'processing', transcript_error: nil)
    data, mime = audio_payload
    response = ask_gemini(data, mime)
    save_result(parse_json(response.dig('candidates', 0, 'content', 'parts', 0, 'text')))
    record_usage(response['usageMetadata'])
    refresh_card
    true
  rescue StandardError => e
    fail!(e)
  end

  private

  def api_key
    @api_key ||= CrmSetting.find_by(account: call.account)&.ai_config&.dig('gemini_api_key')
  end

  def skip!(reason)
    call.update!(transcript_status: 'skipped', transcript_error: reason)
    refresh_card
    false
  end

  def fail!(error)
    Rails.logger.warn("[CEVICO calls] transcrição da ligação #{call.id} falhou: #{error.class}: #{error.message}")
    call.update!(transcript_status: 'failed', transcript_error: short_error(error))
    refresh_card
    false
  rescue StandardError => e
    Rails.logger.error("[CEVICO calls] não deu nem para marcar a falha da ligação #{call.id}: #{e.message}")
    false
  end

  def short_error(error)
    text = error.message.to_s.strip
    text = 'A transcrição falhou. Tente de novo mais tarde.' if text.blank?
    text.truncate(180)
  end

  def refresh_card
    Crm::Calls::CardMessageBuilder.new(call).perform
  end

  # webm gravado pelo navegador vira ogg (mesmo opus, só o container) quando o ffmpeg existe
  def audio_payload
    bytes = call.recording.download
    mime = (call.recording.content_type.presence || call.recording_mime.presence || 'audio/webm').to_s
    return [bytes, mime] unless mime.include?('webm') && ffmpeg?

    remuxed = remux_to_ogg(bytes)
    remuxed ? [remuxed, 'audio/ogg'] : [bytes, mime]
  end

  def ffmpeg?
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, 'ffmpeg')) }
  end

  def remux_to_ogg(bytes)
    Dir.mktmpdir('cevico-call') do |dir|
      input = File.join(dir, 'in.webm')
      output = File.join(dir, 'out.ogg')
      File.binwrite(input, bytes)
      _out, err, status = Open3.capture3('ffmpeg', '-y', '-loglevel', 'error', '-i', input, '-c', 'copy', output)
      unless status.success? && File.exist?(output) && File.size(output).positive?
        Rails.logger.warn("[CEVICO calls] ffmpeg não remuxou a gravação #{call.id}: #{err.to_s.truncate(200)}")
        return nil
      end
      File.binread(output)
    end
  end

  def ask_gemini(data, mime)
    body = {
      contents: [{ parts: [{ text: PROMPT }, { inline_data: { mime_type: mime, data: Base64.strict_encode64(data) } }] }],
      generationConfig: { temperature: 0.2, response_mime_type: 'application/json' }
    }
    response = HTTParty.post(GEMINI_URL, query: { key: api_key }, headers: { 'Content-Type' => 'application/json' },
                                         body: body.to_json, timeout: 180)
    raise "Gemini respondeu com erro #{response.code}: #{gemini_error(response)}" unless response.success?

    response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
  end

  def gemini_error(response)
    parsed = response.parsed_response
    (parsed.is_a?(Hash) ? parsed.dig('error', 'message') : nil).to_s.truncate(120)
  end

  # o modelo às vezes embrulha o JSON em ```json ... ``` ou conversa antes/depois
  def parse_json(text)
    raise 'O Gemini não devolveu texto.' if text.blank?

    clean = text.to_s.gsub(/```(?:json)?/i, '').strip
    candidates = [clean, clean[(clean.index('{') || 0)..(clean.rindex('}') || -1)]]
    candidates.each do |candidate|
      parsed = JSON.parse(candidate)
      return parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      next
    end
    raise 'O Gemini respondeu fora do formato esperado.'
  end

  def save_result(parsed)
    transcript = parsed['transcricao'].to_s.strip
    raise 'O Gemini não conseguiu transcrever o áudio.' if transcript.blank?

    summary = [parsed['resumo'].to_s.strip.presence, next_step(parsed['proximo_passo'])].compact.join("\n")
    call.update!(transcript: transcript, summary: summary.presence, transcript_status: 'done',
                 transcript_error: nil, transcribed_at: Time.current)
  end

  def next_step(raw)
    step = raw.to_s.strip
    return nil if step.blank? || step.casecmp('nenhum').zero?

    "Próximo passo: #{step}"
  end

  def record_usage(usage)
    return if usage.blank?

    input = usage['promptTokenCount'].to_i
    output = usage['candidatesTokenCount'].to_i
    cost = ((input * PRICE_IN) + (output * PRICE_OUT)) / 1_000_000.0
    Crm::AiUsage.create!(account: call.account, agent_key: AGENT_KEY, model: MODEL,
                         input_tokens: input, output_tokens: output, cost_usd: cost.round(6))
  rescue StandardError => e
    Rails.logger.warn("[Crm::AiUsage] falhou ao registrar a transcrição: #{e.message}")
  end
end
