# Página PÚBLICA do formulário CEVICO — o paciente acessa pelo link
# assinado enviado no WhatsApp, sem login. O token identifica o
# formulário e o contato; a resposta cai amarrada ao paciente.
class CevicoFormsController < ActionController::Base
  protect_from_forgery with: :null_session
  layout false

  before_action :load_form

  def show
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

    render json: { ok: true, id: response.id }
  rescue StandardError => e
    Rails.logger.error "[CevicoForms] submit: #{e.message}"
    render json: { ok: false }, status: :unprocessable_entity
  end

  private

  def load_form
    data = Crm::Form.verify_token(params[:token].to_s)
    @form = data && Crm::Form.find_by(id: data[:form_id], slug: params[:slug], active: true)

    return render plain: 'Formulário não encontrado ou link inválido.', status: :not_found if @form.nil?

    @contact = data[:contact_id] && Contact.find_by(id: data[:contact_id], account_id: data[:account_id])
    @first_name = @contact&.name.to_s.split(' ').first
  end
end
