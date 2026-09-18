# 📞 Ligações de WhatsApp (item 167): lista/detalhe para o time, atender/
# recusar/desligar (o WebRTC roda no navegador — aqui só falamos com a Meta
# e gravamos o estado), gravação + transcrição, ligar para o paciente
# (permissão → connect) e o Dashboard de Ligações (área de relatórios).
class Api::V1::Accounts::Crm::CallsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  PER_PAGE = 50

  before_action -> { require_capability(:reports) }, only: [:dashboard]
  before_action :set_call, only: [:show, :accept, :reject, :hangup, :recording, :transcribe]
  before_action :set_contact, only: [:initiate, :request_permission, :permission_status]

  def index
    scope = filtered_scope
    total = scope.count
    calls = scope.recent_first.with_attached_recording.includes(:contact, :user, :conversation)
                 .offset((page - 1) * per_page).limit(per_page)
    render json: { calls: calls.map(&:to_payload), meta: { total: total, page: page, per_page: per_page } }
  end

  def show
    render json: @call.to_payload(include_sdp: @call.ringing?)
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

  # filtros da lista: status, direção, atendente, paciente e período (preset da régua ou since/until)
  def filtered_scope
    scope = Crm::Call.where(account_id: Current.account.id)
    apply_period(apply_id_filters(apply_kind_filters(scope)))
  end

  def apply_kind_filters(scope)
    scope = scope.where(status: params[:status]) if Crm::Call.statuses.key?(params[:status].to_s)
    scope = scope.where(direction: params[:direction]) if Crm::Call.directions.key?(params[:direction].to_s)
    scope
  end

  def apply_id_filters(scope)
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    scope
  end

  def apply_period(scope)
    range = list_range
    range ? scope.in_period(*range) : scope
  end

  def list_range
    preset_range = standard_period_range
    return preset_range if preset_range

    since = safe_period_parse(params[:since])
    until_at = list_until
    return nil if since.nil? && until_at.nil?

    [since || Time.zone.at(0), until_at || PERIOD_TZ.now.end_of_day]
  end

  # "até" só com a data (sem hora) = o dia inteiro
  def list_until
    until_at = safe_period_parse(params[:until])
    return until_at if until_at.nil? || params[:until].to_s.length > 10

    until_at.end_of_day
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
