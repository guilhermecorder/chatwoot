# Resumo da conversa para o card do painel lateral: estágio do CRM,
# etiquetas, métricas de responsividade e a análise de IA (armazenada).
class Api::V1::Accounts::Crm::ConversationSummariesController < Api::V1::Accounts::BaseController
  before_action :conversation

  # GET /api/v1/accounts/:account_id/crm/conversation_summary?conversation_id=X
  def show
    render json: summary_json
  end

  # POST /api/v1/accounts/:account_id/crm/conversation_summary/analyze
  def analyze
    result = Crm::ConversationInsightService.new(conversation: @conversation).call

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      attrs = @conversation.additional_attributes || {}
      @conversation.update!(additional_attributes: attrs.merge('ai_insight' => result.stringify_keys))
      render json: { ai: result }
    end
  end

  private

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  def summary_json
    {
      stage: stage_json,
      labels: @conversation.label_list,
      metrics: metrics_json,
      ai: @conversation.additional_attributes&.[]('ai_insight'),
      ai_configured: ai_configured?
    }
  end

  # card do CRM do contato: em qual coluna/funil ele está
  def stage_json
    contact_id = @conversation.contact_id
    return nil if contact_id.blank?

    card = Crm::Contact.joins(:pipeline, :stage)
                       .where(crm_pipelines: { account_id: Current.account.id }, contact_id: contact_id)
                       .order('crm_pipelines.position')
                       .first
    return nil unless card

    {
      stage_name: card.stage.name,
      stage_color: card.stage.color,
      pipeline_name: card.pipeline.name
    }
  end

  def metrics_json
    scope = @conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
    incoming = scope.where(message_type: :incoming).count
    outgoing = scope.where(message_type: :outgoing).count
    last_patient_at = scope.where(message_type: :incoming).maximum(:created_at)

    {
      patient_messages: incoming,
      clinic_messages: outgoing,
      # % de respostas do paciente em relação ao que a clínica manda
      responsiveness: outgoing.positive? ? [(incoming.to_f / outgoing * 100).round, 100].min : nil,
      last_patient_message_at: last_patient_at
    }
  end

  def ai_configured?
    (CrmSetting.find_by(account: Current.account)&.ai_config || {})['api_key'].present?
  end
end
