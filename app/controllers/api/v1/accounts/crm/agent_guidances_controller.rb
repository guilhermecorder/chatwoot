# ✍️ Orientações dos atendentes de IA (rodada 191, só admin): lista, cria,
# edita, aplica no Roteiro (ou nos passos do agente), ignora e reabre.
# Aplicar = foto do texto atual (Crm::ScriptVersion) + linha formatada no
# fim da seção escolhida.
class Api::V1::Accounts::Crm::AgentGuidancesController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action :require_administrator!
  before_action :guidance, only: %i[update destroy apply ignore reopen]

  LIMIT = 200

  # GET /crm/agent_guidances?agent_key=&status=
  def index # rubocop:disable Metrics/AbcSize
    scope = Crm::AgentGuidance.where(account: Current.account)
    scope = scope.where(agent_key: params[:agent_key].to_s) if params[:agent_key].present?
    counts = scope.group(:status).count
    scope = scope.where(status: params[:status].to_s) if Crm::AgentGuidance::STATUSES.include?(params[:status].to_s)
    items = scope.includes(:created_by, :applied_by).recent.limit(LIMIT)
    render json: {
      guidances: items.map(&:to_payload),
      counts: Crm::AgentGuidance::STATUSES.index_with { |s| counts[s] || 0 },
      sections: Crm::AgentGuidance::SECTIONS.map { |k| { key: k, title: Crm::AgentGuidance::SECTION_TITLES[k] } }
    }
  end

  def create
    g = Crm::AgentGuidance.new(guidance_params.merge(account: Current.account, created_by: Current.user))
    g.source = 'manual' unless Crm::AgentGuidance::SOURCES.include?(g.source)
    g.save!
    render json: g.to_payload, status: :created
  end

  def update
    @guidance.update!(guidance_params.except(:source, :agent_key).merge(guidance_params.slice(:agent_key).compact_blank))
    render json: @guidance.to_payload
  end

  def destroy
    @guidance.destroy!
    head :no_content
  end

  # POST /crm/agent_guidances/:id/apply — devolve a orientação + a seção nova
  def apply
    new_text = @guidance.apply!(by: Current.user)
    render json: {
      guidance: @guidance.to_payload,
      section: { key: @guidance.target_section, title: Crm::AgentGuidance::SECTION_TITLES[@guidance.target_section], text: new_text },
      agent_key: @guidance.agent_key,
      script_updated_at: Crm::CevicoScript.updated_at(Current.account)
    }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def ignore
    @guidance.update!(status: 'ignored')
    render json: @guidance.to_payload
  end

  # volta para pendente (uma ignorada, ou uma aplicada que vai ser refeita —
  # o texto já escrito no Roteiro fica; o admin ajusta no card se quiser)
  def reopen
    @guidance.update!(status: 'pending', applied_at: nil, applied_by: nil)
    render json: @guidance.to_payload
  end

  private

  def guidance
    @guidance = Crm::AgentGuidance.where(account: Current.account).find(params[:id])
  end

  def guidance_params
    params.permit(:agent_key, :source, :conversation_id, :message_id, :patient_excerpt, :agent_text,
                  :ideal_reply, :rule, :target_section).to_h.symbolize_keys
  end
end
