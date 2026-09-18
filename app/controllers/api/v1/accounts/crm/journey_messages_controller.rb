# 🗺️ Mensagens da jornada (item 168): CRUD das regras, prévia com paciente
# real, teste para o meu número, "planejar agora" e a configuração geral
# (locais/horário/teto). Leitura livre para o time; escrita = área
# concedível `campaigns` (a jornada é a evolução da Campanha).
class Api::V1::Accounts::Crm::JourneyMessagesController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  before_action -> { require_capability(:campaigns) }, only: %i[create update destroy test_send plan_now update_settings]
  before_action :message, only: %i[update destroy test_send plan_now]

  def index
    messages = Crm::JourneyMessage.where(account: Current.account).ordered
    render json: {
      journey_messages: messages.map { |m| m.to_payload.merge(stats: stats_for(m)) },
      steps: Crm::JourneyMessage::STEPS, kinds: Crm::JourneyMessage::KIND_LABELS,
      tokens: Crm::Journey::Variables::TOKENS, settings: settings.to_h,
      today: today_summary
    }
  end

  def create
    m = Crm::JourneyMessage.new(message_params.merge(account: Current.account, created_by: Current.user))
    m.position = (Crm::JourneyMessage.where(account: Current.account).maximum(:position) || 0) + 1
    m.save!
    render json: m.to_payload.merge(stats: stats_for(m)), status: :created
  end

  def update
    @message.update!(message_params)
    render json: @message.to_payload.merge(stats: stats_for(@message))
  end

  def destroy
    @message.destroy!
    head :no_content
  end

  # prévia com um paciente REAL do próximo evento (ou o contact_id pedido):
  # variáveis preenchidas + texto final, sem enviar nada
  def preview
    m = Crm::JourneyMessage.new(message_params.merge(account: Current.account))
    event = sample_event(m)
    return render json: { found: false, message: 'Nenhum paciente com esse gatilho nos próximos dias.' } if event.nil?

    contact = Current.account.contacts.find_by(id: event[:contact_id])
    values = Crm::Journey::Variables.build(event[:source], contact, settings)
    render json: { found: true, contact: { id: contact&.id, name: contact&.name, phone_number: contact&.phone_number },
                   variables: values, text: preview_text(m, values) }
  end

  # manda a mensagem para o MEU número (ou o telefone informado) com as
  # variáveis do exemplo — o jeito de ver a mensagem chegando no celular
  def test_send
    phone = params[:phone].to_s.delete('^0-9')
    return render json: { ok: false, error: 'Informe o telefone com DDD.' }, status: :unprocessable_entity if phone.length < 10

    contact = Task.match_contact(Current.account, phone) || create_test_contact(phone)
    event = sample_event(@message)
    send = Crm::JourneySend.new(account: Current.account, journey_message: @message, contact: contact,
                                source: event&.dig(:source), event_key: "teste:#{SecureRandom.hex(4)}",
                                scheduled_for: Time.current, status: 'queued')
    send.save!
    outcome = Crm::Journey::Dispatcher.new(account: Current.account).dispatch(send)
    render json: { ok: outcome == :sent, outcome: outcome, send: send.reload.to_payload }
  end

  # roda o planejador só para esta mensagem (útil logo depois de criar)
  def plan_now
    created = Crm::Journey::Planner.new(account: Current.account).plan_message(@message)
    render json: { created: created, today: today_summary }
  end

  def settings_show
    render json: { settings: settings.to_h }
  end

  def update_settings
    crm = CrmSetting.find_or_create_by!(account: Current.account)
    cfg = crm.agenda_config || {}
    cfg['journey'] = apply_settings_params(cfg['journey'] || {})
    crm.update!(agenda_config: cfg)
    render json: { settings: Crm::Journey::Settings.new(Current.account, crm_settings: crm).to_h }
  end

  private

  def message
    @message = Crm::JourneyMessage.where(account: Current.account).find(params[:id])
  end

  def settings
    @settings ||= Crm::Journey::Settings.new(Current.account)
  end

  def apply_settings_params(journey)
    journey['places'] = sanitize_places(params[:places]) if params.key?(:places)
    journey['hours'] = sanitize_hours(params[:hours]) if params.key?(:hours)
    journey['daily_cap'] = params[:daily_cap].to_i.clamp(1, 5000) if params.key?(:daily_cap)
    journey['quiet_labels'] = quiet_labels_param if params.key?(:quiet_labels)
    journey
  end

  def quiet_labels_param
    Array(params[:quiet_labels]).map { |l| l.to_s.strip }.compact_blank.first(20)
  end

  PERMITTED = %i[name active step inbox_id approval expects_reply confirm_label decline_alert respect_quiet position].freeze
  AUDIENCE_LISTS = %w[include_label_ids include_stage_ids exclude_label_ids exclude_stage_ids].freeze

  def message_params
    raw = params.require(:journey_message).permit(*PERMITTED, trigger: {}, audience: {}, content: {})
    raw[:trigger] = sanitize_trigger(raw[:trigger]) if raw.key?(:trigger)
    raw[:audience] = sanitize_audience(raw[:audience]) if raw.key?(:audience)
    raw[:content] = sanitize_content(raw[:content]) if raw.key?(:content)
    raw[:inbox_id] = Current.account.inboxes.find_by(id: raw[:inbox_id])&.id if raw.key?(:inbox_id)
    raw
  end

  def sanitize_trigger(raw)
    hash = raw.to_h
    { 'kind' => hash['kind'].to_s, 'offset_days' => hash['offset_days'].to_i, 'at' => hash['at'].to_s.strip.presence || '10:00',
      'stage_id' => hash['stage_id'].presence&.to_i, 'label' => hash['label'].to_s.strip.presence }.compact
  end

  def sanitize_audience(raw)
    hash = raw.to_h
    lists = AUDIENCE_LISTS.index_with { |k| Array(hash[k]).map(&:to_i).select(&:positive?) }
    period = %w[period_field period_from period_to].index_with { |k| hash[k].to_s.presence }
    lists.merge(period).compact
  end

  def sanitize_content(raw)
    hash = raw.to_h
    template = hash['template_params']
    template = template.to_h if template.respond_to?(:to_h)
    { 'mode' => hash['mode'].to_s.presence || 'template', 'template_params' => template.presence,
      'message_preview' => hash['message_preview'].to_s.strip[0, 2000].presence, 'text' => hash['text'].to_s.strip[0, 2000] }.compact
  end

  def sanitize_places(raw)
    hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    out = %w[default tatuape paulista].select { |k| hash[k].present? }.index_with { |k| clean_place(hash[k]) }
    return out if hash['clinics'].blank?

    out['clinics'] = (hash['clinics'] || {}).to_h.first(30).to_h { |k, v| [k.to_s.strip[0, 80], clean_place(v)] }
    out
  end

  def clean_place(value)
    place = value.to_h
    { 'unidade' => place['unidade'].to_s.strip[0, 120], 'endereco' => place['endereco'].to_s.strip[0, 300] }
  end

  def sanitize_hours(raw)
    h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    start_at = h['start'].to_s.strip
    end_at = h['end'].to_s.strip
    valid = [start_at, end_at].all? { |v| v.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/) } && start_at < end_at
    valid ? { 'start' => start_at, 'end' => end_at } : Crm::Journey::Settings::DEFAULT_HOURS.dup
  end

  def stats_for(message)
    counts = Hash.new(0).merge(message.sends.group(:status).count)
    replies = Hash.new(0).merge(message.sends.where.not(reply: nil).group(:reply).count)
    { sent: counts['sent'], failed: counts['failed'], skipped: counts['skipped'] + counts['expired'],
      pending: counts['queued'] + counts['pending_review'], confirmed: replies['confirmed'], declined: replies['declined'],
      last_sent_at: message.sends.maximum(:sent_at)&.iso8601 }
  end

  def today_summary
    tz = Crm::Journey::Settings::TZ
    scope = Crm::JourneySend.where(account: Current.account).for_day(tz.now.to_date, tz)
    scope.group(:status).count
  end

  # próximo evento real (hoje → +7 dias) para preencher a prévia/teste
  def sample_event(message)
    if params[:contact_id].present?
      contact = Current.account.contacts.find_by(id: params[:contact_id])
      return contact && { contact_id: contact.id, source: nil }
    end
    (0..7).each do |ahead|
      planner = Crm::Journey::Planner.new(account: Current.account, now: Crm::Journey::Settings::TZ.now + ahead.days)
      event = planner.events_for(message).first
      return event if event
    end
    nil
  end

  def preview_text(message, values)
    Crm::Journey::Dispatcher.new(account: Current.account).preview_text(message, values)
  end

  def create_test_contact(phone)
    Current.account.contacts.create!(name: "Teste jornada #{Current.user.available_name}", phone_number: "+#{phone}")
  end
end
