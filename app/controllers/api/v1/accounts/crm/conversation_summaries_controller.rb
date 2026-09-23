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
      # merge atômico: não pode apagar o marcador do follow-up nem a pausa
      Cevico::AttributeMerge.merge!(@conversation) do |attrs|
        attrs.merge('ai_insight' => result.stringify_keys)
      end
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

  # POST /crm/conversation_summary/toggle_responder — 🤖 item 207 (23/09):
  # botão "ligar/desligar a IA para esta pessoa" dentro da conversa. Mesmo
  # estado que o 👍/mensagem humana usam (cevico_atendente_wa), com nota
  # interna dizendo quem foi. Assim a equipe conversa com o paciente e religa
  # o Atendente sem mandar emoji para ele.
  def toggle_responder
    paused = ActiveModel::Type::Boolean.new.cast(params[:paused])
    value = paused ? { 'paused' => true, 'reason' => 'botao', 'by' => Current.user.name, 'at' => Time.current.iso8601 } : {}
    Cevico::AttributeMerge.merge!(@conversation) { |attrs| attrs.merge(Crm::ResponderAgentJob::STATE_KEY => value) }
    note = if paused
             "⏸ Atendente IA do WhatsApp DESLIGADO nesta conversa por #{Current.user.name} (botão do painel)."
           else
             "▶️ Atendente IA do WhatsApp LIGADO nesta conversa por #{Current.user.name} (botão do painel)."
           end
    @conversation.messages.create!(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id,
                                   message_type: :activity, private: true, content: note)
    render json: { responder: responder_json }
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
      followup: followup_json,
      responder: responder_json
    }
  end

  # estado do follow-up para ESTA conversa: pausado para o paciente? e quais
  # robôs alcançam esta conversa (por coluna do card ou por caixa)
  # 🤖 estado do Atendente IA do WhatsApp NESTA conversa (item 207)
  REASON_TEXT = {
    'humano_assumiu' => 'pausou sozinho quando o atendimento humano respondeu',
    'chamar_humano' => 'o agente pediu atendimento humano',
    'botao' => 'desligado pelo botão'
  }.freeze

  def responder_json # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cfg = CrmSetting.find_by(account: Current.account)&.ai_config || {}
    agents = (cfg['agents'] || {}).slice(*CrmListener::RESPONDER_KEYS).select do |_k, a|
      a['enabled'] == true && Array(a['inbox_ids']).map(&:to_i).include?(@conversation.inbox_id)
    end
    state = @conversation.additional_attributes&.[](Crm::ResponderAgentJob::STATE_KEY) || {}
    {
      available: agents.any?,
      live: agents.values.any? { |a| Crm::ResponderAgentJob.live_mode?(a) },
      paused: state['paused'] == true,
      reason: state['reason'],
      reason_text: REASON_TEXT[state['reason'].to_s] || state['reason'],
      by: state['by'],
      at: state['at']
    }
  end

  def followup_json
    paused = @conversation.contact&.additional_attributes&.[]('cevico_followup_paused')
    {
      paused: paused.present?,
      paused_by: paused.is_a?(Hash) ? paused['by'] : nil,
      bots: followup_bots_json
    }
  end

  # robôs que alcançam ESTA conversa (por coluna do card ou por caixa), cada
  # um com a PREVISÃO (rodada 158): a mesma decisão do robô, sem enviar nada —
  # o que já saiu, o que foi pulado, quando sai a próxima e por quê
  def followup_bots_json
    card = find_card
    job = Crm::FollowupBotJob.new
    Current.account.crm_followup_bots.order(:id).filter_map do |bot|
      next unless bot.inbox_id.blank? || bot.inbox_id == @conversation.inbox_id
      next if bot.stage_scoped? && !(card && bot.stage_id == card.stage_id)

      { id: bot.id, name: bot.name, active: bot.active, forecast: safe_forecast(job, bot) }
    end
  end

  def safe_forecast(job, bot)
    job.forecast(bot, @conversation)
  rescue StandardError => e
    Rails.logger.warn("[CEVICO followup] previsão conversa #{@conversation.id}: #{e.message}")
    nil
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
