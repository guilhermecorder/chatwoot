# Formulários CEVICO: montagem (admin), agregação das respostas para o
# dashboard e geração de insights de marketing com IA.
class Api::V1::Accounts::Crm::FormsController < Api::V1::Accounts::BaseController
  before_action :check_admin
  before_action :form, only: [:update, :destroy, :summary, :generate_insights, :preview_link]

  def index
    forms = Current.account.crm_forms.order(created_at: :desc)
    counts = Crm::FormResponse.where(crm_form_id: forms.map(&:id)).group(:crm_form_id).count
    render json: forms.map { |f| form_json(f, counts[f.id] || 0) }
  end

  def create
    f = Current.account.crm_forms.create!(form_params)
    render json: form_json(f, 0), status: :created
  end

  def update
    @form.update!(form_params)
    render json: form_json(@form, @form.responses.count)
  end

  def destroy
    @form.destroy!
    head :no_content
  end

  # link de teste (token do próprio admin, sem contato vinculado)
  def preview_link
    render json: { link: @form.public_link_for(nil) }
  end

  # GET summary?since=YYYY-MM-DD — agrega respostas por pergunta
  def summary
    responses = scoped_responses
    render json: {
      total: responses.size,
      first_response_at: responses.map(&:created_at).min,
      last_response_at: responses.map(&:created_at).max,
      questions: aggregate_questions(responses),
      ai_insight: @form.ai_insight.presence
    }
  end

  # IA lê as respostas (principalmente abertas) e sintetiza dores,
  # desejos e objeções — os insights de marketing
  def generate_insights
    result = Crm::FormInsightService.new(form: @form, responses: scoped_responses).call
    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      @form.update!(ai_insight: result.stringify_keys)
      render json: { ai_insight: result }
    end
  end

  private

  def check_admin
    return if Current.account_user.administrator?

    render json: { error: 'Apenas administradores podem gerenciar formulários.' }, status: :forbidden
  end

  def form
    @form ||= Current.account.crm_forms.find(params[:id])
  end

  def form_params
    params.permit(:name, :active, :intro_title, :intro_text, :thank_you_text,
                  questions: [:id, :label, :type, :required, :text, :color, { options: [] }])
  end

  def scoped_responses
    scope = @form.responses.where.not(completed_at: nil).order(created_at: :desc)
    scope = scope.where('created_at >= ?', Date.parse(params[:since]).beginning_of_day) if params[:since].present?
    scope.to_a
  end

  # agrega por pergunta ATUAL do formulário, casando pelo id gravado
  # no snapshot da resposta
  def aggregate_questions(responses)
    # cards de mensagem não têm resposta — ficam fora do dashboard
    @form.questions.reject { |q| q['type'] == 'message' }.map do |q|
      values = responses.filter_map do |r|
        ans = r.answers.find { |a| a['id'] == q['id'] }
        v = ans && ans['value']
        v.presence
      end

      base = { id: q['id'], label: q['label'], type: q['type'], answered: values.size }

      case q['type']
      when 'choice', 'yesno'
        base.merge(counts: tally_sorted(values))
      when 'multi'
        base.merge(counts: tally_sorted(values.flatten))
      when 'scale'
        nums = values.map(&:to_i)
        base.merge(
          counts: tally_sorted(values.map(&:to_s)),
          average: nums.any? ? (nums.sum.to_f / nums.size).round(1) : nil
        )
      else # text
        base.merge(answers: values.first(200))
      end
    end
  end

  def tally_sorted(values)
    values.tally.sort_by { |_, c| -c }.to_h
  end

  def form_json(f, responses_count)
    {
      id: f.id,
      name: f.name,
      slug: f.slug,
      active: f.active,
      intro_title: f.intro_title,
      intro_text: f.intro_text,
      thank_you_text: f.thank_you_text,
      questions: f.questions,
      responses_count: responses_count,
      sent_count: f.sent_count,
      funnel_stats: f.funnel_stats || {},
      has_insight: f.ai_insight.present?,
      created_at: f.created_at
    }
  end
end
