# 🤖📞 Webhooks públicos do Agente de Ligação (item 169), chamados pela
# ElevenLabs durante e depois da ligação:
#   POST /webhooks/cevico/voice/:account_id/tools/:tool  — ferramenta (X-Cevico-Token)
#   POST /webhooks/cevico/voice/:account_id/initiation   — dados de início (X-Cevico-Token)
#   POST /webhooks/cevico/voice/:account_id/post_call    — pós-chamada (ElevenLabs-Signature HMAC)
# Erro de ferramenta volta como { ok: false, erro } com 200 — a IA precisa
# LER o motivo para se corrigir; 401 só quando o token/assinatura não bate.
class Webhooks::CevicoVoiceController < ActionController::API
  TOKEN_HEADER = 'X-Cevico-Token'.freeze
  SIGNATURE_HEADER = 'ElevenLabs-Signature'.freeze
  MAX_SIGNATURE_AGE = 30.minutes

  before_action :load_account
  before_action :verify_tools_token!, only: [:tool, :initiation]
  before_action :verify_signature!, only: [:post_call]

  def tool
    result = Crm::VoiceAgent::ToolsService.new(account: @account, tool: params[:tool], params: body,
                                               conversation_id: body['conversa_id']).perform
    render json: result
  end

  # início da ligação: quem está ligando → nome/próxima consulta + primeira frase com o nome
  def initiation
    caller = body['caller_id'].to_s
    found = Crm::VoiceAgent::ToolsService.new(account: @account, tool: 'buscar_paciente', params: { 'telefone' => caller },
                                              conversation_id: body['conversation_id']).perform
    first_name = found[:primeiro_nome].to_s
    render json: {
      type: 'conversation_initiation_client_data',
      dynamic_variables: {
        paciente_nome: found[:nome].to_s, primeiro_nome: first_name, proxima_consulta: found[:proxima_consulta].to_s,
        telefone: caller.gsub(/\D/, ''), campanha_objetivo: ''
      },
      conversation_config_override: { agent: { first_message: personalized_first_message(first_name) } }
    }
  end

  def post_call
    Crm::VoiceAgent::PostCallJob.perform_later(@account.id, body)
    head :ok
  end

  private

  def load_account
    @account = Account.find_by(id: params[:account_id])
    head :not_found unless @account
  end

  def settings
    @settings ||= Crm::VoiceAgent::Settings.new(@account)
  end

  def raw_body
    @raw_body ||= request.raw_post.to_s
  end

  def body
    @body ||= begin
      parsed = raw_body.present? ? JSON.parse(raw_body) : {}
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end

  def verify_tools_token!
    token = settings.tools_token.to_s
    given = request.headers[TOKEN_HEADER].to_s
    return if token.present? && given.present? && ActiveSupport::SecurityUtils.secure_compare(token, given)

    head :unauthorized
  end

  # ElevenLabs-Signature: t=<unix>,v0=<hex(HMAC_SHA256(secret, "t.body"))>
  def verify_signature!
    secret = settings.webhook_secret.to_s
    timestamp, signature = signature_parts(request.headers[SIGNATURE_HEADER])
    return head :unauthorized if secret.blank? || timestamp.blank? || signature.blank?
    return head :unauthorized if (Time.current.to_i - timestamp.to_i).abs > MAX_SIGNATURE_AGE

    expected = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{raw_body}")}"
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  def signature_parts(header)
    return [nil, nil] if header.blank?

    # header malformado (par sem "=") vira 401, nunca 500
    parts = header.to_s.split(',').filter_map do |pair|
      key, value = pair.strip.split('=', 2)
      [key, value] if value.present?
    end.to_h
    [parts['t'], parts['v0'].present? ? "v0=#{parts['v0']}" : nil]
  end

  def personalized_first_message(first_name)
    text = settings.first_message
    return text if first_name.blank? || text.include?(first_name)

    text.sub(/\AOlá!?\s*/i, "Olá, #{first_name}! ")
  end
end
