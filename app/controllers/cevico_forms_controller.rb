# Página PÚBLICA do formulário CEVICO — o paciente acessa pelo link
# assinado enviado no WhatsApp, sem login. O token identifica o
# formulário e o contato; a resposta cai amarrada ao paciente.
class CevicoFormsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  protect_from_forgery with: :null_session
  layout false

  before_action :load_form

  def show
    # domínio oficial configurado → link antigo (host da VPS) redireciona
    # 301 pro oficial; o token vai junto no caminho, nada quebra
    if Cevico::PublicSite.configured? && !Cevico::PublicSite.official_host?(request.host)
      return redirect_to "#{Cevico::PublicSite.base_url}#{request.fullpath}",
                         status: :moved_permanently, allow_other_host: true
    end

    @form.bump_funnel!('open')
    render :show
  end

  def submit
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
    data = Crm::Form.verify_token(params[:token].to_s)
    @form = data && Crm::Form.find_by(id: data[:form_id], slug: params[:slug], active: true)

    return render plain: 'Formulário não encontrado ou link inválido.', status: :not_found if @form.nil?

    @contact = data[:contact_id] && Contact.find_by(id: data[:contact_id], account_id: data[:account_id])
    @first_name = @contact&.name.to_s.split.first
  end
end
