# Página PÚBLICA do formulário CEVICO — o paciente acessa sem login, por
# dois caminhos:
#   1. link ASSINADO (enviado pelo sistema no WhatsApp): o token identifica
#      formulário + contato; a resposta cai amarrada ao paciente.
#   2. link LIMPO (/forms/pre-avaliacao): o paciente se identifica com nome
#      + WhatsApp no começo; o sistema acha o paciente pelo telefone (mesmo
#      critério do resto do CEVICO) e atrela a resposta ao card. Telefone
#      desconhecido → cria o paciente + card em "Agendamento de Consulta"
#      (decisão 01/09: o link só vai pra quem decidiu agendar).
class CevicoFormsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  protect_from_forgery with: :null_session
  layout false

  before_action :load_form

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
    # link limpo: sem paciente colado no token → a identificação do
    # formulário (nome + WhatsApp) diz quem é. Telefone inválido = 422
    # com mensagem que a tela mostra no próprio card.
    if @contact.nil? && @ask_identity
      @contact = resolve_identity_contact
      return if performed? # resolve_identity_contact já respondeu o erro
    end

    answers = Array(params[:answers]).map do |a|
      a.permit(:id, :label, :type, :value, value: []).to_h
    end

    response = @form.responses.create!(
      account_id: @form.account_id,
      contact_id: @contact&.id,
      answers: answers,
      completed_at: Time.current
    )

    @form.bump_funnel!('done')
    render json: { ok: true, id: response.id }
  rescue StandardError => e
    Rails.logger.error "[CevicoForms] submit: #{e.message}"
    render json: { ok: false }, status: :unprocessable_entity
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
  # critério do AppointmentRecorder). Não achou → cria paciente + card na
  # coluna "Agendamento de Consulta" com origem 'formulario'.
  def resolve_identity_contact
    name = params.dig(:identity, :name).to_s.strip[0, 120]
    digits = params.dig(:identity, :phone).to_s.gsub(/\D/, '')

    return render_identity_error if name.blank? || digits.length < 10 || digits.length > 13

    contact = find_contact_by_phone(digits)
    if contact
      # nome só COMPLETA cadastro sem nome — nunca sobrescreve o existente
      contact.update(name: name) if contact.name.blank?
      return contact
    end

    create_contact_with_card(name, digits)
  end

  def find_contact_by_phone(digits)
    @form.account.contacts
         .where.not(phone_number: [nil, ''])
         .where("regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
         .order(:id)
         .find { |c| Crm::AppointmentRecorder.same_phone_line?(digits, c.phone_number) }
  end

  def create_contact_with_card(name, digits)
    e164 = digits.start_with?('55') && digits.length >= 12 ? "+#{digits}" : "+55#{digits}"
    contact = @form.account.contacts.create!(name: name, phone_number: e164)

    stage = booking_stage
    if stage
      Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: stage.pipeline_id) do |card|
        card.stage_id = stage.id
        card.origin = 'formulario'
      end
    end
    contact
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # corrida (dois envios) ou telefone já cadastrado com outra máscara:
    # tenta achar de novo antes de desistir
    find_contact_by_phone(digits) || (render_identity_error && nil)
  end

  def render_identity_error
    render json: { ok: false, error: 'identity' }, status: :unprocessable_entity
  end

  def booking_stage
    scope = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @form.account_id })
    scope.where('crm_stages.name ILIKE ?', '%agendamento%consulta%').order(:position).first ||
      scope.where('crm_stages.name ILIKE ?', '%agendamento%').order(:position).first ||
      scope.order(:position).first
  end
end
