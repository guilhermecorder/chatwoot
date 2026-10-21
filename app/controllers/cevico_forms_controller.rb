# Página PÚBLICA do formulário CEVICO — o paciente acessa sem login, por
# dois caminhos:
#   1. link ASSINADO (enviado pelo sistema no WhatsApp): o token identifica
#      formulário + contato; a resposta cai amarrada ao paciente.
#   2. link LIMPO (/forms/pre-avaliacao): o paciente se identifica com nome
#      + WhatsApp no começo; o sistema acha o paciente pelo telefone (mesmo
#      critério do resto do CEVICO). 🔐 Rodada 4 da auditoria (#119):
#      · telefone de cadastro EXISTENTE → a resposta nasce "não confirmada" e
#        um CÓDIGO sai pela conversa em que o paciente já fala com a clínica;
#        acertou o código (POST /verify) → confirmada (+ card em "Agendamento
#        de Consulta" se ainda não tinha). O cadastro nunca muda.
#      · telefone DESCONHECIDO → cria o paciente SEM card (fora dos
#        indicadores) e com marca pendente + tarefa "ligar e confirmar" para
#        a equipe; teto diário por formulário.
#      · LGPD: a página responde IGUAL para qualquer telefone (sempre o card
#        "se este número já conversa com a gente, enviamos um código") —
#        ninguém descobre pelo formulário quem é paciente da clínica.
#      Tudo em Crm::FormVerification.
class CevicoFormsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  protect_from_forgery with: :null_session
  layout false
  # 🔐 CSP só-relatar + sem iframe (rodada 171). O formulário ainda usa
  # onclick= inline — aparece no log até virar addEventListener.
  include Cevico::PublicSecurity

  before_action :load_form

  # 🔐 achado #118: limite do JSON de respostas (jsonb fica fora da trava de
  # 20k do ApplicationRecord) e tamanho de cada valor
  MAX_ANSWERS_BYTES = 32.kilobytes
  MAX_VALUE_CHARS = 2000
  MAX_MULTI_ITEMS = 50

  def show
    # domínio oficial configurado → link antigo (host da VPS) redireciona
    # 301 pro oficial; o caminho vai junto, nada quebra
    if Cevico::PublicSite.configured? && !Cevico::PublicSite.official_host?(request.host)
      return redirect_to "#{Cevico::PublicSite.base_url}#{request.fullpath}",
                         status: :moved_permanently, allow_other_host: true
    end

    @form.bump_funnel!('open')
    render :show
  end

  def submit
    # 🔐 achado #118: id/label/type vêm das perguntas do banco — do cliente
    # só o `value`; resposta grande demais é recusada (422 too_large) ANTES
    # de identificar o paciente, para não criar cadastro/card sem resposta
    answers = sanitized_answers
    return render json: { ok: false, error: 'too_large' }, status: :unprocessable_entity if answers.to_json.bytesize > MAX_ANSWERS_BYTES

    # link limpo: sem paciente colado no token → a identificação do
    # formulário (nome + WhatsApp) diz quem é. Telefone inválido = 422
    # com mensagem que a tela mostra no próprio card.
    if @contact.nil? && @ask_identity
      @contact = resolve_identity_contact
      return if performed? # resolve_identity_contact já respondeu o erro

      @identity_asked = true
      answers += identity_meta # a marca "não confirmada" só existe depois de saber quem é
    end

    response = @form.responses.create!(
      account_id: @form.account_id,
      contact_id: @contact&.id,
      answers: answers,
      completed_at: Time.current
    )

    @form.bump_funnel!('done')
    # 🔐 #119: cadastro existente → código pela conversa do paciente; paciente
    # novo → marca pendente + tarefa. A página recebe SEMPRE o mesmo
    # `verify: {status:'check'}` (sem final do número): nada no JSON diz se o
    # telefone é de paciente. O código em si NUNCA vai no JSON.
    render json: { ok: true, id: response.id, verify: after_identity(response) }.compact
  rescue StandardError => e
    Rails.logger.error "[CevicoForms] submit: #{e.message}"
    render json: { ok: false }, status: :unprocessable_entity
  end

  # 🔐 Rodada 4 (#119): o paciente digita o código recebido no WhatsApp.
  # 5 tentativas em 10 min (Redis); errou tudo ou venceu → a resposta fica
  # "não confirmada" para a equipe conferir (nada muda no cadastro). Sem
  # código guardado responde igual a código errado (LGPD — ver verify!).
  def verify
    record = @form.responses.find_by(id: params[:response_id])
    return render json: { ok: false, error: 'expired' }, status: :unprocessable_entity if record.nil?

    result = Crm::FormVerification.verify!(record, params[:code])
    return render json: { ok: true } if result[:ok]

    render json: { ok: false, error: result[:error], remaining: result[:remaining] }.compact, status: :unprocessable_entity
  end

  # beacon de retenção: o paciente CHEGOU no card X (1 por card por visita)
  # — alimenta o gráfico de abandono do hub dos Formulários
  def track
    qid = params[:question_id].to_s[0, 40]
    @form.bump_funnel!("q:#{qid}") if qid.present? && @form.questions.any? { |q| q['id'] == qid }
    head :no_content
  end

  private

  def load_form
    params[:token].present? ? load_form_from_token : load_form_from_slug
    return if performed?

    @first_name = @contact&.name.to_s.split.first
  end

  def load_form_from_token
    data = Crm::Form.verify_token(params[:token].to_s)
    @form = data && Crm::Form.find_by(id: data[:form_id], slug: params[:slug], active: true)
    return not_found if @form.nil?

    @contact = data[:contact_id] && Contact.find_by(id: data[:contact_id], account_id: data[:account_id])
    # token genérico (contact_id nulo — ex.: link de teste antigo) também
    # pede identificação: melhor que resposta órfã
    @ask_identity = @contact.nil?
  end

  # link limpo: qualquer pessoa com o endereço abre; identifica-se dentro
  def load_form_from_slug
    @form = Crm::Form.find_by(slug: params[:slug], active: true)
    return not_found if @form.nil?

    @contact = nil
    @ask_identity = true
  end

  def not_found
    render plain: 'Formulário não encontrado ou link inválido.', status: :not_found
  end

  # ── identificação pelo telefone (link limpo) ────────────────────────────
  # Acha o paciente pelos últimos 8 dígitos + confirmação de linha (mesmo
  # critério do AppointmentRecorder). Não achou → cria o paciente SEM card
  # (#119: só ganha card quando prova o telefone ou escreve no WhatsApp).
  def resolve_identity_contact
    name = params.dig(:identity, :name).to_s.strip[0, 120]
    digits = params.dig(:identity, :phone).to_s.gsub(/\D/, '')

    return render_identity_error if name.blank? || digits.length < 10 || digits.length > 13

    contact = find_contact_by_phone(digits)
    if contact
      # 🔐 achado #118: cadastro existente NÃO muda (nem o nome) — quem digitou
      # pode não ser o dono do telefone. O nome digitado vai na marca da resposta.
      @unverified_identity = true
      return contact
    end

    # 🔐 #119: teto diário global de cadastros novos por formulário. Passou do
    # teto: NÃO cria paciente, mas guarda a resposta solta (sem paciente, com
    # o telefone digitado na marca) e responde igual aos outros casos — um
    # erro só para telefone desconhecido contaria quem é paciente (LGPD).
    unless Crm::FormVerification.new_contact_allowed?(@form)
      @capped_phone = digits
      @unverified_identity = true
      return nil
    end

    Crm::Stamp.with(via: 'paciente') { create_pending_contact(name, digits) } # 🏷️ item 322
  end

  # depois de gravar a resposta do link limpo: paciente novo ganha a marca
  # pendente + tarefa para a equipe; cadastro existente recebe o código pela
  # conversa dele. A página recebe SEMPRE { status: 'check' } (LGPD).
  def after_identity(response)
    return nil unless @identity_asked

    if @new_contact
      Crm::FormVerification.mark_pending!(@contact, form: @form, response: response, informed_name: params.dig(:identity, :name))
      Crm::FormVerification.open_pending_task!(@contact, form: @form)
    elsif @unverified_identity && @contact
      Crm::FormVerification.start!(response)
    end
    { status: 'check' }
  end

  # Reconstrói cada resposta a partir da PERGUNTA do banco (id/label/type) e
  # aceita do cliente só o `value` (texto curto ou lista de textos curtos).
  def sanitized_answers
    questions = @form.questions.reject { |q| q['type'] == 'message' }.index_by { |q| q['id'].to_s }
    Array(params[:answers]).filter_map do |a|
      next unless a.respond_to?(:permit)

      raw = a.permit(:id, :value, value: []).to_h
      question = questions[raw['id'].to_s]
      next if question.nil?

      { 'id' => question['id'], 'label' => question['label'], 'type' => question['type'],
        'value' => sanitized_value(raw['value']) }
    end
  end

  # link limpo que caiu num cadastro que JÁ EXISTIA: ninguém provou que é o
  # dono do telefone → a resposta nasce "não confirmada" (selo para a equipe
  # e o médico). Link assinado (token com o paciente) continua confirmado.
  def identity_meta
    return [] unless @unverified_identity

    via = @new_contact || @capped_phone ? Crm::FormResponse::VIA_NEW_CONTACT : Crm::FormResponse::VIA_CLEAN_LINK
    [Crm::FormResponse.unverified_meta(informed_name: params.dig(:identity, :name), via: via, informed_phone: @capped_phone)]
  end

  def sanitized_value(value)
    if value.is_a?(Array)
      value.first(MAX_MULTI_ITEMS).map { |v| v.to_s[0, MAX_VALUE_CHARS] }
    else
      value.to_s[0, MAX_VALUE_CHARS]
    end
  end

  def find_contact_by_phone(digits)
    @form.account.contacts
         .where.not(phone_number: [nil, ''])
         .where("regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
         .order(:id)
         .find { |c| Crm::AppointmentRecorder.same_phone_line?(digits, c.phone_number) }
  end

  # 🔐 #119: telefone desconhecido vira paciente SEM card — não entra na
  # coluna de agendamento nem nos indicadores de etapa; o card nasce quando
  # ele escreve no WhatsApp (CrmListener) ou confirma o código. A resposta
  # dele também nasce "não confirmada" (via 'cadastro_novo').
  def create_pending_contact(name, digits)
    e164 = digits.start_with?('55') && digits.length >= 12 ? "+#{digits}" : "+55#{digits}"
    contact = @form.account.contacts.create!(name: name, phone_number: e164)
    @new_contact = true
    @unverified_identity = true
    contact
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # corrida (dois envios) ou telefone já cadastrado com outra máscara:
    # tenta achar de novo antes de desistir. Se achou, é um cadastro que já
    # existia → a resposta também nasce "não confirmada" (achado #118).
    # Nos dois casos ninguém novo foi criado: a vaga do teto do dia volta.
    Crm::FormVerification.release_new_contact_slot!(@form)
    existing = find_contact_by_phone(digits)
    if existing
      @unverified_identity = true
      return existing
    end

    render_identity_error
    nil
  end

  def render_identity_error
    render json: { ok: false, error: 'identity' }, status: :unprocessable_entity
  end
end
