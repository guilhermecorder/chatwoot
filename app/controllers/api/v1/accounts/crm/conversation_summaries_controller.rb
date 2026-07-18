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

  # POST /crm/conversation_summary/sales_help — Consultor Comercial ao vivo:
  # identifica a objeção do paciente e sugere respostas para a vendedora
  def sales_help
    result = Crm::SalesCoachService.new(conversation: @conversation).coach

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: { sales: result }
    end
  end

  # POST /crm/conversation_summary/move_stage — move o card do contato de
  # coluna DIRETO da conversa (mesmos disparos de automação do board)
  def move_stage
    card = find_card
    return render json: { error: 'Contato ainda não tem card no CRM.' }, status: :unprocessable_entity if card.blank?

    new_stage = Crm::Stage.joins(:pipeline)
                          .where(crm_pipelines: { account_id: Current.account.id })
                          .find(params[:stage_id])
    previous_stage = card.stage

    if new_stage.id != card.stage_id
      # card muda de funil junto, se a coluna for de outro funil
      card.update!(stage_id: new_stage.id, pipeline_id: new_stage.pipeline_id)

      CrmAutomationTriggerService.new(crm_contact: card, new_stage: new_stage,
                                      previous_stage: previous_stage, event_type: 'card_entered').call
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: previous_stage,
                                      previous_stage: previous_stage, event_type: 'card_left').call
    end

    render json: { stage: stage_json }
  end

  # POST /crm/conversation_summary/toggle_followup — TRAVA individual:
  # a atendente pausa/reativa o follow-up SÓ para este paciente (todos os
  # robôs param de cutucá-lo). Aberto a qualquer atendente — é o freio de
  # emergência de quem está vendo a conversa.
  def toggle_followup
    contact = @conversation.contact
    return render json: { error: 'Conversa sem contato.' }, status: :unprocessable_entity if contact.blank?

    paused = ActiveModel::Type::Boolean.new.cast(params[:paused])
    # merge atômico: gravar a pausa não pode ser apagado por outra escrita
    # concorrente no contato (sexo/nps/fechamento) — senão o robô volta a cutucar
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      if paused
        attrs.merge('cevico_followup_paused' => { 'by' => Current.user.name, 'at' => Time.current.iso8601 })
      else
        attrs.except('cevico_followup_paused')
      end
    end

    render json: { followup: followup_json }
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
      ai_configured: ai_configured?,
      followup: followup_json
    }
  end

  # estado do follow-up para ESTA conversa: pausado para o paciente? e quais
  # robôs alcançam esta conversa (por coluna do card ou por caixa)
  def followup_json
    contact = @conversation.contact
    paused = contact&.additional_attributes&.[]('cevico_followup_paused')
    card = find_card

    bots = Current.account.crm_followup_bots.order(:id).select do |bot|
      inbox_ok = bot.inbox_id.blank? || bot.inbox_id == @conversation.inbox_id
      stage_ok = !bot.stage_scoped? || (card && bot.stage_id == card.stage_id)
      inbox_ok && stage_ok
    end

    {
      paused: paused.present?,
      paused_by: paused.is_a?(Hash) ? paused['by'] : nil,
      bots: bots.map { |b| { id: b.id, name: b.name, active: b.active } }
    }
  end

  def find_card
    contact_id = @conversation.contact_id
    return nil if contact_id.blank?

    Crm::Contact.joins(:pipeline, :stage)
                .where(crm_pipelines: { account_id: Current.account.id }, contact_id: contact_id)
                .order('crm_pipelines.position')
                .first
  end

  # card do CRM do contato: em qual coluna/funil ele está + as colunas do
  # funil (para os botões de mover direto da conversa)
  def stage_json
    card = find_card
    return nil unless card

    {
      stage_id: card.stage_id,
      stage_name: card.stage.name,
      stage_color: card.stage.color,
      pipeline_name: card.pipeline.name,
      stages: card.pipeline.stages.order(:position).map do |s|
        { id: s.id, name: s.name, color: s.color }
      end
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
