# Fecha a ligação da assistente virtual com o que a ElevenLabs manda no
# webhook pós-chamada (assinado, via Crm::VoiceAgent::PostCallJob):
#   post_call_transcription → cria/atualiza a Crm::Call (direção, telefone,
#     duração, transcrição "Assistente:/Paciente:", resumo, resultado,
#     análise crua, custo), card na conversa da caixa da clínica, cable,
#     Crm::AiUsage e fecha o contato da campanha (done + resultado)
#   post_call_audio → mp3 em base64 vira a gravação (Active Storage)
#   call_initiation_failure → contato da campanha vira failed/no_permission
# Idempotente pelo conversation_id (reentrega só atualiza).
class Crm::VoiceAgent::PostCallService # rubocop:disable Metrics/ClassLength
  attr_reader :account, :payload

  def initialize(account:, payload:)
    @account = account
    @payload = (payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload.to_h).deep_stringify_keys
  end

  def perform
    case payload['type']
    when 'post_call_transcription' then handle_transcription
    when 'post_call_audio' then handle_audio
    when 'call_initiation_failure' then handle_initiation_failure
    else
      Rails.logger.info("[CEVICO voice] evento ignorado: #{payload['type']}")
      nil
    end
  end

  private

  def data = payload['data'] || {}
  def conversation_id = data['conversation_id'].to_s
  def metadata = (data['metadata'] || {}).to_h
  def analysis = (data['analysis'] || {}).to_h

  def dynamic_vars
    (data.dig('conversation_initiation_client_data', 'dynamic_variables') || data['dynamic_variables'] || {}).to_h
  end

  def settings
    @settings ||= Crm::VoiceAgent::Settings.new(account)
  end

  # ── transcrição (fim da ligação) ──────────────────────────────────────────
  def handle_transcription
    return nil if conversation_id.blank?

    call = find_or_build_call
    return nil unless call

    apply_transcription(call)
    call.save!
    finish(call)
    call
  end

  def find_or_build_call
    Crm::Call.find_by(account_id: account.id, provider_call_id: conversation_id) || build_call
  end

  def build_call
    inbox = settings.call_inbox
    unless inbox
      Rails.logger.warn("[CEVICO voice] conta #{account.id} sem caixa WhatsApp: ligação #{conversation_id} não gravada")
      return nil
    end

    finder = conversation_finder(inbox)
    Crm::Call.new(
      account: account, inbox: inbox, contact: finder&.contact || contact, conversation: finder&.conversation,
      meta_call_id: "el:#{conversation_id}", provider: 'elevenlabs', provider_call_id: conversation_id, handled_by: 'ai',
      direction: direction, campaign_id: campaign_contact&.call_campaign_id, wa_id: wa_id.presence, display_name: display_name
    )
  end

  def display_name
    contact&.name.presence || dynamic_vars['paciente_nome'].presence
  end

  # paciente + conversa na caixa da clínica (só com telefone conhecido)
  def conversation_finder(inbox)
    return nil if wa_id.length < 8

    Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: wa_id, name: display_name, contact: contact)
  end

  def campaign_contact
    return @campaign_contact if defined?(@campaign_contact)

    @campaign_contact = Crm::CallCampaignContact.for_conversation(account, conversation_id) || campaign_contact_from_vars
  end

  # sem conversation_id casado (falha de início): acha pela campanha/contato das variáveis
  def campaign_contact_from_vars
    campaign_id = dynamic_vars['campanha_id'].to_i
    contact_id = dynamic_vars['contato_id'].to_i
    return nil unless campaign_id.positive? && contact_id.positive?

    Crm::CallCampaignContact.joins(:call_campaign)
                            .where(cevico_call_campaigns: { account_id: account.id, id: campaign_id })
                            .find_by(contact_id: contact_id)
  end

  def contact
    return @contact if defined?(@contact)

    @contact = campaign_contact&.contact || (wa_id.length >= 8 ? Task.match_contact(account, wa_id) : nil)
  end

  # telefone: WhatsApp da ElevenLabs → variável telefone → quem ligou → contato da campanha
  def wa_id
    @wa_id ||= [metadata.dig('whatsapp', 'whatsapp_user_id'), dynamic_vars['telefone'], dynamic_vars['system__caller_id'],
                campaign_contact&.contact&.phone_number].map { |v| v.to_s.gsub(/\D/, '') }.find(&:present?) || ''
  end

  def direction
    raw = metadata.dig('whatsapp', 'direction') || metadata.dig('phone_call', 'direction')
    return raw.to_s == 'outbound' ? :outbound : :inbound if raw.present?

    campaign_contact ? :outbound : :inbound
  end

  def apply_transcription(call)
    apply_timing(call)
    apply_final_status(call, missed?)
    apply_content(call)
    call.contact ||= contact
    call.add_event('post_call_transcription', status: data['status'], termination_reason: metadata['termination_reason'])
  end

  def duration
    metadata['call_duration_secs'].to_i
  end

  def apply_timing(call)
    started = metadata['start_time_unix_secs'].to_i
    call.started_at = Time.zone.at(started) if started.positive?
    call.started_at ||= Time.current
    call.duration = duration
    call.ended_at = call.started_at + duration.seconds
  end

  # transcrição, resumo, resultado, análise crua e custo
  def apply_content(call)
    apply_transcript(call)
    call.summary = analysis['transcript_summary'].presence || call.summary
    call.outcome = resolve_outcome(call, missed?)
    call.analysis = raw_analysis
    call.cost_usd = metadata['cost_fiat'].to_f.round(6) if metadata['cost_fiat'].present?
  end

  def apply_transcript(call)
    call.transcript = format_transcript(data['transcript'])
    call.transcript_status = call.transcript.present? ? 'done' : 'skipped'
    call.transcribed_at = Time.current if call.transcript.present?
  end

  # falhou ou zero segundos = ninguém falou com ninguém
  def missed?
    data['status'].to_s == 'failed' || duration.zero?
  end

  def apply_final_status(call, missed)
    if missed
      call.status = :missed
      call.end_reason = 'not_answered'
      call.answered_at = nil
    else
      call.status = :completed
      call.end_reason = 'completed'
      call.answered_at ||= call.started_at
    end
  end

  # "Assistente: …" / "Paciente: …", uma linha por fala; ferramentas entre parênteses
  def format_transcript(entries)
    Array(entries).flat_map do |entry|
      role = entry['role'].to_s == 'agent' ? 'Assistente' : 'Paciente'
      lines = []
      lines << "#{role}: #{entry['message'].to_s.strip}" if entry['message'].to_s.strip.present?
      Array(entry['tool_calls']).each do |tc|
        name = tc['tool_name'] || tc['name']
        lines << "(ferramenta: #{name})" if name.present?
      end
      lines
    end.join("\n")
  end

  # resultado: o que a IA registrou na ligação > data_collection da ElevenLabs > pelo estado
  def resolve_outcome(call, missed)
    return call.outcome if call.outcome.present?

    collected = analysis.dig('data_collection_results', 'resultado')
    collected = collected['value'] if collected.is_a?(Hash)
    return collected.to_s if Crm::Call::OUTCOME_LABELS.key?(collected.to_s)
    return 'nao_atendeu' if missed
    return 'transferido' if metadata['termination_reason'].to_s.downcase.include?('transfer')

    'outro'
  end

  def raw_analysis
    { 'status' => data['status'], 'agent_id' => data['agent_id'], 'termination_reason' => metadata['termination_reason'],
      'call_successful' => analysis['call_successful'], 'transcript_summary' => analysis['transcript_summary'],
      'data_collection_results' => analysis['data_collection_results'] || {},
      'evaluation_criteria_results' => analysis['evaluation_criteria_results'] || {},
      'cost' => metadata['cost'], 'cost_fiat' => metadata['cost_fiat'], 'dynamic_variables' => dynamic_vars }
  end

  def finish(call)
    Crm::Calls::CardMessageBuilder.new(call).perform
    if call.missed? && call.inbound?
      call.conversation&.update!(status: :open) if call.conversation && !call.conversation.open?
      broadcast('cevico_call.missed', call: call.to_payload, reason: call.end_reason)
    end
    broadcast('cevico_call.ended', call: call.to_payload)
    record_usage(call)
    close_campaign_contact(call)
    settings.persist_state!(last_call_at: Time.current.iso8601)
  end

  # uma linha por ligação (o Painel dos agentes lê daqui); custo em US$ da ElevenLabs
  def record_usage(call)
    Crm::AiUsage.create!(account: account, agent_key: 'voice', model: settings.llm, input_tokens: 0, output_tokens: 0,
                         cost_usd: call.cost_usd.to_f.round(6))
  rescue StandardError => e
    Rails.logger.warn("[Crm::AiUsage] falhou ao registrar a ligação: #{e.message}")
  end

  def close_campaign_contact(call)
    cc = campaign_contact
    return unless cc

    cc.update!(status: 'done', outcome: cc.outcome.presence || call.outcome, call_id: call.id, error: nil)
    apply_label(cc)
    cc.call_campaign.refresh_stats!
    cc.call_campaign.finish_if_done!
  end

  def apply_label(campaign_contact)
    title = campaign_contact.call_campaign.apply_label.to_s.strip.downcase
    return if title.blank?

    account.labels.find_or_create_by!(title: title)
    campaign_contact.contact.label_list.add(title)
    campaign_contact.contact.save!
  rescue StandardError => e
    Rails.logger.error("[CEVICO voice] etiqueta '#{title}' contato #{campaign_contact.contact_id}: #{e.message}")
  end

  # ── áudio (mp3 em base64) ─────────────────────────────────────────────────
  def handle_audio
    return nil if conversation_id.blank?

    call = find_or_build_call
    return nil unless call

    b64 = data['full_audio'].to_s
    call.started_at ||= Time.current
    call.save! if call.new_record? || call.changed?
    return call if b64.blank?

    call.recording.attach(io: StringIO.new(Base64.decode64(b64)), filename: "ligacao-#{conversation_id}.mp3", content_type: 'audio/mpeg')
    call.update!(recording_mime: 'audio/mpeg', recording_duration: call.duration)
    Crm::Calls::CardMessageBuilder.new(call).perform
    call
  end

  # ── a ElevenLabs não conseguiu iniciar a ligação (campanha) ───────────────
  def handle_initiation_failure
    reason = (data['failure_reason'] || data['error'] || data['message'] || 'a ElevenLabs não conseguiu iniciar a ligação').to_s
    call = fail_call(reason)
    fail_campaign_contact(reason, call)
    call
  end

  def fail_call(reason)
    return nil if conversation_id.blank?

    call = Crm::Call.find_by(account_id: account.id, provider_call_id: conversation_id)
    return nil unless call

    call.update!(status: :failed, end_reason: 'failed', ended_at: Time.current, error_message: reason.truncate(500))
    Crm::Calls::CardMessageBuilder.new(call).perform
    call
  end

  # recusa de permissão vira no_permission; o resto, failed
  def fail_campaign_contact(reason, call)
    cc = campaign_contact
    return unless cc

    status = reason.downcase.include?('permission') ? 'no_permission' : 'failed'
    cc.update!(status: status, error: reason.truncate(500), call_id: cc.call_id || call&.id)
    cc.call_campaign.refresh_stats!
    cc.call_campaign.finish_if_done!
  end

  def broadcast(event, payload)
    Crm::Calls::Broadcaster.push(account, event, payload)
  end
end
