# 📞 Ligações de WhatsApp (item 167): lista/detalhe para o time, atender/
# recusar/desligar (o WebRTC roda no navegador — aqui só falamos com a Meta
# e gravamos o estado), gravação + transcrição, ligar para o paciente
# (permissão → connect) e o Dashboard de Ligações (área de relatórios).
class Api::V1::Accounts::Crm::CallsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  PER_PAGE = 50
  EXPORT_LIMIT = 5000
  LIST_INCLUDES = %i[contact user conversation inbox].freeze

  before_action -> { require_capability(:reports) }, only: [:dashboard]
  before_action :set_call, only: [:show, :accept, :reject, :hangup, :recording, :transcribe, :returned]
  before_action :set_contact, only: [:initiate, :request_permission, :permission_status]

  # live=1 → só o que está tocando/em atendimento agora (ignora os filtros)
  def index
    return render json: { calls: live_scope.map(&:to_payload), meta: { live: true } } if params[:live].present?

    scope = filtered_scope
    total = scope.count
    calls = scope.recent_first.with_attached_recording.includes(*LIST_INCLUDES)
                 .offset((page - 1) * per_page).limit(per_page)
    render json: { calls: calls.map(&:to_payload), meta: { total: total, page: page, per_page: per_page } }
  end

  # ambiente Chamadas (item 176): números do período com comparação, ao vivo,
  # perdidas de hoje sem retorno — aberto ao time (o menu é quem esconde)
  def overview
    since, until_at = dashboard_range
    render json: Crm::Calls::DashboardService.new(account: Current.account, since: since, until_at: until_at,
                                                  period: params[:preset].presence || 'month').overview
  end

  # marca uma perdida como retornada (ligou de volta por fora / mandou mensagem)
  def returned
    return render json: { error: 'Só ligações já encerradas podem ser marcadas.' }, status: :unprocessable_entity unless @call.final?

    @call.mark_returned!(Current.user, note: params[:note].to_s.first(200))
    Crm::Calls::CardMessageBuilder.new(@call).perform
    broadcast('cevico_call.ended', call: @call.to_payload)
    render json: @call.to_payload
  end

  # CSV do histórico com os mesmos filtros da lista (até 5.000 linhas)
  def export
    calls = filtered_scope.recent_first.includes(*LIST_INCLUDES).limit(EXPORT_LIMIT)
    send_data Crm::Calls::CsvExport.new(calls).to_csv, type: 'text/csv; charset=utf-8',
                                                       filename: "chamadas-#{Time.zone.today.iso8601}.csv"
  end

  def show
    render json: @call.to_payload(include_sdp: @call.ringing?, include_events: true)
  end

  # atender: trava a linha para dois atendentes não pegarem a mesma chamada
  def accept
    conflict = nil
    @call.with_lock do
      next take_call! if @call.ringing?

      conflict = taken_message
    end
    return render json: { error: conflict }, status: :conflict if conflict

    broadcast('cevico_call.taken', call_id: @call.id, user_id: Current.user.id, user_name: Current.user.available_name)
    render json: @call.to_payload
  rescue Crm::Calls::MetaError => e
    render json: { error: "A Meta não deixou atender: #{e.message}" }, status: :unprocessable_entity
  end

  def reject
    return render json: { error: 'Esta chamada já foi encerrada.' }, status: :conflict unless @call.ringing?

    safely_meta { meta_client(@call).reject(@call.meta_call_id) }
    @call.add_event('rejected_by_agent', user_id: Current.user.id)
    @call.update!(status: :rejected, end_reason: 'rejected', ended_at: Time.current, user: Current.user, sdp_offer: nil)
    finish_and_render
  end

  # desligar: manda o terminate para a Meta e já fecha por aqui (o webhook
  # terminate, quando vier, só acerta duração/horários com os dados da Meta)
  def hangup
    return render json: { error: 'Esta chamada já foi encerrada.' }, status: :conflict if @call.final?

    safely_meta { meta_client(@call).terminate(@call.meta_call_id) }
    status = @call.answered_at ? :completed : :canceled
    @call.add_event('hangup_by_agent', user_id: Current.user.id)
    @call.update!(status: status, end_reason: status == :completed ? 'hangup' : 'canceled', ended_at: Time.current,
                  sdp_offer: nil, sdp_answer: nil)
    @call.update!(duration: @call.talk_seconds) if @call.answered_at && @call.duration.to_i.zero?
    finish_and_render
  end

  # gravação feita no navegador (webm/ogg): anexa, atualiza o card e manda transcrever
  def recording
    file = params[:recording]
    return render json: { error: 'Nenhuma gravação foi enviada.' }, status: :unprocessable_entity unless file.respond_to?(:tempfile)

    @call.recording.attach(file)
    @call.update!(recording_mime: file.content_type.to_s.presence, recording_duration: params[:duration].to_i)
    queue_transcription if settings.transcribe?
    Crm::Calls::CardMessageBuilder.new(@call).perform
    render json: @call.to_payload
  end

  def transcribe
    return render json: { error: 'Esta ligação não tem gravação.' }, status: :unprocessable_entity unless @call.recording.attached?

    queue_transcription
    Crm::Calls::CardMessageBuilder.new(@call).perform
    render json: @call.to_payload
  end

  def dashboard
    since, until_at = dashboard_range
    render json: Crm::Calls::DashboardService.new(account: Current.account, since: since, until_at: until_at,
                                                  period: params[:preset].presence || 'month').call
  end

  # ligar para o paciente: precisa da permissão dele na Meta + caixa configurada
  def initiate
    result = outbound.initiate(params[:sdp_offer].to_s)
    return render json: result.except(:ok), status: :unprocessable_entity unless result[:ok]

    render json: result[:call].to_payload
  end

  def request_permission
    result = outbound.request_permission
    return render json: result, status: :unprocessable_entity unless result[:ok]

    render json: { ok: true }
  end

  def permission_status
    render json: outbound.permission_status
  end

  private

  def set_call
    @call = Crm::Call.where(account_id: Current.account.id).find(params[:id])
  end

  def set_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def settings
    @settings ||= Crm::Calls::Settings.new(Current.account)
  end

  def outbound
    @outbound ||= Crm::Calls::OutboundService.new(account: Current.account, user: Current.user, contact: @contact,
                                                  preferred_inbox_id: params[:inbox_id])
  end

  def meta_client(call)
    Crm::Calls::MetaClient.new(call.inbox.channel, simulated: call.simulated)
  end

  def safely_meta
    yield
  rescue Crm::Calls::MetaError => e
    Rails.logger.warn("[CEVICO calls] Meta recusou a ação: #{e.message}")
  end

  # avisa a Meta e marca quem atendeu (roda dentro do lock da linha)
  def take_call!
    meta_client(@call).accept(@call.meta_call_id, params[:sdp_answer].to_s)
    @call.add_event('accepted_by_agent', user_id: Current.user.id)
    @call.update!(status: :accepted, user: Current.user, answered_at: Time.current, sdp_offer: nil)
  end

  def taken_message
    taker = @call.user&.available_name
    taker ? "Esta chamada já foi atendida por #{taker}." : 'Esta chamada já foi encerrada.'
  end

  def finish_and_render
    Crm::Calls::CardMessageBuilder.new(@call).perform
    broadcast('cevico_call.ended', call: @call.to_payload)
    render json: @call.to_payload
  end

  def queue_transcription
    @call.update!(transcript_status: 'pending', transcript_error: nil)
    Crm::Calls::TranscriptionJob.perform_later(@call.id)
  end

  def broadcast(event, data)
    Crm::Calls::Broadcaster.push(Current.account, event, data)
  end

  def live_scope
    Crm::Call.where(account_id: Current.account.id).live.includes(*LIST_INCLUDES)
  end

  # filtros da lista/CSV (situação, direção, atendente, caixa, busca, período)
  def filtered_scope
    Crm::Calls::ListFilter.new(Current.account, params).scope
  end

  def dashboard_range
    standard_period_range || legacy_range
  end

  def legacy_range
    now = PERIOD_TZ.now
    case params[:preset]
    when 'week' then [now.beginning_of_week, now.end_of_week]
    when 'all' then [Time.zone.at(0), now.end_of_day]
    else [now.beginning_of_month, now.end_of_day]
    end
  end

  def page
    [params[:page].to_i, 1].max
  end

  def per_page
    params[:limit].to_i.between?(1, PER_PAGE) ? params[:limit].to_i : PER_PAGE
  end
end
