# PLANEJADOR (item 168): para cada mensagem ativa acha os EVENTOS de hoje
# (cirurgia amanhã, consulta hoje, entrou na coluna há 3 dias…) e cria o
# Crm::JourneySend correspondente — 1 por paciente × evento (event_key
# único), com a hora de envio da regra. Quem exige aprovação nasce
# pending_review (Fila de hoje); o resto nasce queued e o Dispatcher manda.
class Crm::Journey::Planner
  TZ = Crm::Journey::Settings::TZ

  attr_reader :account, :now

  def initialize(account:, now: nil)
    @account = account
    @now = (now || TZ.now).in_time_zone(TZ)
  end

  # devolve { message_id => criados }
  def perform(messages = nil)
    scope = messages || Crm::JourneyMessage.where(account: account).active
    scope.each_with_object({}) do |message, created|
      created[message.id] = plan_message(message)
    rescue StandardError => e
      Rails.logger.error("[CEVICO jornada] planejar '#{message.name}': #{e.message}")
      created[message.id] = 0
    end
  end

  def plan_message(message)
    events = events_for(message)
    return 0 if events.empty?

    allowed = message.audience_filter? ? message.audience_contact_ids.to_set : nil
    scheduled_for = send_time(message)
    events.count do |event|
      next false if allowed&.exclude?(event[:contact_id])

      create_send(message, event, scheduled_for)
    end
  end

  # [{ contact_id, source, event_key }]
  def events_for(message)
    target = today - message.offset_days
    case message.kind
    when 'surgery' then surgery_events(target)
    when 'appointment' then appointment_events(target)
    when 'stage' then stage_events(message, target)
    when 'label' then label_events(message, target)
    when 'call_missed' then missed_call_events
    else []
    end
  end

  private

  def today = now.to_date

  def send_time(message)
    hh, mm = message.send_at.split(':').map(&:to_i)
    TZ.local(today.year, today.month, today.day, hh, mm)
  end

  def create_send(message, event, scheduled_for)
    Crm::JourneySend.create!(
      account: account, journey_message: message, contact_id: event[:contact_id],
      source: event[:source], event_key: event[:event_key], scheduled_for: scheduled_for,
      status: message.review? ? 'pending_review' : 'queued'
    )
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def surgery_events(target)
    Crm::OftalmofacilSurgery.where(account_id: account.id, status_kind: 'agendada', surgery_date: target)
                            .where.not(contact_id: nil)
                            .map { |s| { contact_id: s.contact_id, source: s, event_key: "surgery:#{s.id}" } }
  end

  def appointment_events(target)
    day_start = TZ.local(target.year, target.month, target.day)
    account.tasks.where(task_type: 'consulta', canceled_at: nil, archived_at: nil)
           .where(due_at: day_start..day_start.end_of_day).where.not(contact_id: nil)
           .map { |t| { contact_id: t.contact_id, source: t, event_key: "task:#{t.id}" } }
  end

  def stage_events(message, target)
    stage_id = message.trigger['stage_id'].to_i
    day_start = TZ.local(target.year, target.month, target.day)
    Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: account.id }, stage_id: stage_id)
                .where(stage_moved_at: day_start..day_start.end_of_day)
                .map { |c| { contact_id: c.contact_id, source: nil, event_key: "stage:#{c.id}:#{target}" } }
  end

  def label_events(message, target)
    tag = ActsAsTaggableOn::Tag.find_by(name: message.trigger['label'].to_s)
    return [] unless tag

    day_start = TZ.local(target.year, target.month, target.day)
    contact_ids = account.contacts.select(:id)
    ActsAsTaggableOn::Tagging.where(tag_id: tag.id, taggable_type: 'Contact', taggable_id: contact_ids, context: 'labels')
                             .where(created_at: day_start..day_start.end_of_day)
                             .map { |t| { contact_id: t.taggable_id, source: nil, event_key: "label:#{t.id}" } }
  end

  # ligações perdidas de HOJE que ninguém retornou (item 167)
  def missed_call_events
    day_start = TZ.local(today.year, today.month, today.day)
    Crm::Call.where(account_id: account.id, direction: :inbound, status: [:missed, :rejected], started_at: day_start..now)
             .where.not(contact_id: nil)
             .reject { |c| Crm::Calls::RadarAlert.returned?(c) }
             .map { |c| { contact_id: c.contact_id, source: c, event_key: "call:#{c.id}" } }
  end
end
