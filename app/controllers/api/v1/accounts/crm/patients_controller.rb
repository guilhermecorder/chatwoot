# ESPAÇO DO PACIENTE (Central do Paciente — Fase 1): a página única do
# paciente. Identidade + LINHA DO TEMPO completa da jornada (anúncio de
# origem → conversas → funil → consultas → indicação → fechamento →
# cirurgia → NPS → formulários → follow-ups) + indicadores. Nada aqui é
# dado novo: é o que o sistema já guarda, costurado pelo contact_id
# unificado da Fase 0.
class Api::V1::Accounts::Crm::PatientsController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  def show
    contact = Current.account.contacts.find(params[:id])
    render json: {
      identity: identity(contact),
      indicators: indicators(contact),
      timeline: timeline(contact),
      label_events: label_events(contact),
      automations: automations(contact),
      updates: updates(contact)
    }
  end

  # POST /crm/patients/:id/update_profile — sexo/nascimento do paciente
  # (seleção manual em botões em linha na página; o Secretário da Agenda
  # também anota sozinho quando percebe pela conversa)
  def update_profile
    contact = Current.account.contacts.find(params[:id])
    attrs = contact.additional_attributes || {}
    attrs['sexo'] = params[:sexo].to_s if params.key?(:sexo) && %w[masculino feminino].include?(params[:sexo].to_s)
    attrs['data_nascimento'] = params[:data_nascimento].to_s if params.key?(:data_nascimento)
    contact.update!(additional_attributes: attrs)
    render json: { profile: patient_profile(contact) }
  end

  private

  def account
    Current.account
  end

  # ---------- identidade ----------

  def identity(contact) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    profile = patient_profile(contact)
    {
      id: contact.id,
      name: contact.name,
      phone_number: contact.phone_number,
      email: contact.email,
      thumbnail: contact.avatar_url,
      labels: contact.label_list,
      created_at: contact.created_at,
      gender: profile[:gender],
      age: profile[:age],
      origin: contact.additional_attributes&.dig('meta_ads')
                     &.slice('headline', 'ad_name', 'source_url', 'thumbnail_url', 'captured_at'),
      cards: patient_cards(contact).map do |card|
        {
          id: card.id,
          pipeline_id: card.pipeline_id,
          pipeline: card.pipeline.name,
          stage: card.stage&.name,
          stage_color: card.stage&.color,
          value: card.value,
          assignee: card.assignee&.name,
          moved_at: card.stage_moved_at
        }
      end
    }
  end

  def patient_cards(contact)
    @patient_cards ||= Crm::Contact.joins(:pipeline)
                                   .where(crm_pipelines: { account_id: account.id }, contact_id: contact.id)
                                   .includes(:stage, :pipeline, :assignee)
                                   .order('crm_pipelines.position')
                                   .to_a
  end

  # sexo + idade do paciente (tema "dopamine" da página): procura nos
  # atributos que a equipe/IA preenche no contato; sem dado = tema neutro
  def patient_profile(contact) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    attrs = (contact.additional_attributes || {}).merge(contact.custom_attributes || {})
    gender_raw = attrs.values_at('gender', 'sexo', 'genero', 'género').compact_blank.first.to_s.downcase
    gender =
      if %w[m masculino male homem].include?(gender_raw) then 'male'
      elsif %w[f feminino female mulher].include?(gender_raw) then 'female'
      end

    age = attrs['idade'].presence&.to_i
    birth_raw = attrs.values_at('date_of_birth', 'birthdate', 'data_nascimento', 'nascimento').compact_blank.first
    if birth_raw.present?
      birth = begin
        Date.parse(birth_raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end
      age = ((Date.current - birth).to_i / 365.25).floor if birth
    end
    { gender: gender, age: age }
  end

  # ---------- etiquetas com data (jornada empilhada) ----------

  # quando cada etiqueta foi ADICIONADA (taggings.created_at) — remoção não
  # deixa registro no core, então a jornada mostra só as adições
  def label_events(contact)
    ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', taggable_id: contact.id, context: 'labels')
                             .includes(:tag)
                             .order(:created_at)
                             .map { |tagging| { label: tagging.tag.name, at: tagging.created_at } }
  end

  # ---------- automações rodando neste contato ----------

  def automations(contact) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    stage_ids = patient_cards(contact).map(&:stage_id)
    labels = contact.label_list.map(&:to_s)

    bots = Crm::FollowupBot.where(account_id: account.id, active: true).select do |bot|
      stage_ok = bot.stage_id.blank? || stage_ids.include?(bot.stage_id)
      required_ok = Array(bot.required_labels).all? { |l| labels.include?(l.to_s) }
      excluded_ok = Array(bot.exclude_labels).none? { |l| labels.include?(l.to_s) }
      stage_ok && required_ok && excluded_ok
    end

    stage_autos = Crm::Automation.where(stage_id: stage_ids, active: true)

    {
      followup_paused: contact.additional_attributes&.dig('cevico_followup_paused').present?,
      followup_bots: bots.map { |b| { id: b.id, name: b.name } },
      stage_automations: stage_autos.map { |a| { id: a.id, name: a.name, action_type: a.action_type } },
      # por quais automações o paciente JÁ PASSOU e quando (trilha gravada
      # pelo CrmAutomationFireJob) — mostra qual automação realmente ajudou
      trail: Array(contact.additional_attributes&.dig('cevico_automation_trail')).reverse.first(30)
    }
  end

  # ---------- atualizações (próximos passos do paciente) ----------

  def updates(contact) # rubocop:disable Metrics/AbcSize
    future = Task.for_patient(account, contact)
                 .where(canceled_at: nil)
                 .where('due_at > ?', Time.current)
                 .order(:due_at).limit(5)
    open_tasks = Task.for_patient(account, contact)
                     .where(status: %i[todo doing])
                     .where('due_at IS NULL OR due_at <= ?', Time.current)
                     .order(created_at: :desc).limit(5)
    notes = contact.notes.includes(:user).order(created_at: :desc).limit(5)

    {
      upcoming: future.map { |t| task_brief(t) },
      open_tasks: open_tasks.map { |t| task_brief(t) },
      notes: notes.map do |n|
        { id: n.id, content: n.content.to_s.truncate(240), author: n.user&.name, at: n.created_at }
      end
    }
  end

  def task_brief(task)
    {
      id: task.id,
      title: task.title,
      task_type: task.task_type,
      modality: task.modality,
      doctor: task.doctor,
      unit: task.unit,
      due_at: task.due_at,
      status: task.status
    }
  end

  # ---------- linha do tempo ----------

  def timeline(contact)
    events = origin_events(contact) +
             conversation_events(contact) +
             funnel_events(contact) +
             agenda_events(contact) +
             closing_events(contact) +
             nps_events(contact) +
             form_events(contact) +
             followup_events(contact)
    events.compact.sort_by { |e| e[:at].to_time }
  end

  def origin_events(contact)
    ads = contact.additional_attributes&.dig('meta_ads')
    return [] if ads.blank? || ads['captured_at'].blank?

    [{
      type: 'origem',
      at: ads['captured_at'],
      headline: ads['headline'],
      ad_name: ads['ad_name'],
      source_url: ads['source_url'],
      thumbnail_url: ads['thumbnail_url']
    }]
  end

  def conversation_events(contact)
    patient_conversations(contact).map do |conv|
      ad = conv.additional_attributes&.dig('meta_ads')
      {
        type: 'conversa',
        at: conv.created_at,
        conversation_id: conv.display_id,
        inbox: conv.inbox&.name,
        channel: conv.inbox&.channel_type&.demodulize,
        status: conv.status,
        last_activity_at: conv.last_activity_at,
        # o anúncio que trouxe ESTA conversa (evidente na jornada)
        ad_name: ad && (ad['ad_name'].presence || ad['headline'].presence)
      }
    end
  end

  def patient_conversations(contact)
    @patient_conversations ||= contact.conversations
                                      .where(account_id: account.id)
                                      .includes(:inbox)
                                      .order(created_at: :asc)
                                      .to_a
  end

  def funnel_events(contact)
    card_ids = patient_cards(contact).map(&:id)
    return [] if card_ids.empty?

    Crm::StageLog.where(crm_contact_id: card_ids, event_type: 'entered')
                 .order(entered_at: :asc)
                 .map do |log|
      {
        type: 'funil',
        at: log.entered_at,
        stage: log.stage_name,
        stage_color: log.stage_color,
        left_at: log.left_at,
        duration_minutes: log.duration_minutes
      }
    end
  end

  # consultas E cirurgias da Agenda — com tipo, comparecimento, indicação e
  # reagendamentos (a consulta indicada carrega a indicação junto)
  def agenda_events(contact)
    patient_tasks(contact).filter_map do |t|
      next unless %w[consulta cirurgia].include?(t.task_type)

      {
        type: t.task_type,
        at: t.due_at || t.created_at,
        task_id: t.id,
        title: t.title,
        modality: t.modality,
        doctor: t.doctor,
        unit: t.unit,
        procedure: t.procedure,
        attendance: t.attendance,
        status: t.status,
        canceled: t.canceled_at.present?,
        rescheduled_count: t.rescheduled_count,
        indicated: t.surgery_indication == 'indicated',
        indicated_procedure: t.indicated_procedure
      }
    end
  end

  def patient_tasks(contact)
    @patient_tasks ||= Task.for_patient(account, contact).order(Arel.sql('due_at ASC NULLS LAST')).to_a
  end

  def closing_events(contact)
    closing = contact.additional_attributes&.dig('surgery_closing')
    return [] if closing.blank? || closing['at'].blank?

    [{
      type: 'fechamento',
      at: closing['at'],
      value: closing['value'],
      payment: closing['payment'],
      surgery_date: closing['surgery_date'],
      note: closing['note']
    }]
  end

  def nps_events(contact)
    nps = contact.additional_attributes&.dig('nps')
    return [] if nps.blank? || nps['at'].blank?

    [{ type: 'nps', at: nps['at'], score: nps['score'], comment: nps['comment'] }]
  end

  def form_events(contact)
    Crm::FormResponse.where(account_id: account.id, contact_id: contact.id)
                     .includes(:form)
                     .map do |resp|
      {
        type: 'formulario',
        at: resp.completed_at || resp.created_at,
        form: resp.form&.name,
        completed: resp.completed_at.present?,
        answers: Array(resp.answers)
      }
    end
  end

  # follow-ups que o paciente RECEBEU (mensagens dos robôs de follow-up)
  def followup_events(contact)
    conv_ids = patient_conversations(contact).map(&:id)
    return [] if conv_ids.empty?

    bot_names = Crm::FollowupBot.where(account_id: account.id).pluck(:id, :name).to_h
    Message.where(conversation_id: conv_ids)
           .where("additional_attributes ? 'cevico_followup_bot_id'")
           .reorder(created_at: :asc)
           .map do |msg|
      {
        type: 'followup',
        at: msg.created_at,
        bot: bot_names[msg.additional_attributes['cevico_followup_bot_id'].to_i],
        content: msg.content.to_s.truncate(160)
      }
    end
  end

  # ---------- indicadores ----------

  def indicators(contact) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    consultas = patient_tasks(contact).select { |t| t.task_type == 'consulta' }
    cirurgias = patient_tasks(contact).select { |t| t.task_type == 'cirurgia' }
    closing = contact.additional_attributes&.dig('surgery_closing') || {}

    {
      first_contact_at: first_contact_at(contact),
      days_in_journey: ((Time.current - first_contact_at(contact)) / 1.day).floor,
      conversations: patient_conversations(contact).size,
      responsiveness: responsiveness(contact),
      funnel: funnel_indicator(contact),
      consultations: consultas.size,
      attended: consultas.count { |t| t.attendance == 'attended' },
      missed: consultas.count { |t| t.attendance == 'missed' },
      rescheduled: consultas.sum(&:rescheduled_count),
      surgeries: cirurgias.size,
      value: closing['value'].presence || patient_cards(contact).filter_map(&:value).max,
      payment: closing['payment'],
      nps: contact.additional_attributes&.dig('nps', 'score')
    }
  end

  def first_contact_at(contact)
    @first_contact_at ||= patient_conversations(contact).first&.created_at || contact.created_at
  end

  # % de resposta do paciente: mensagens recebidas ÷ enviadas pela clínica
  # (acima de 100% = paciente fala mais que a clínica). ⚠️ default_scope de
  # Message quebra GROUP BY → reorder(nil).
  def responsiveness(contact)
    conv_ids = patient_conversations(contact).map(&:id)
    return nil if conv_ids.empty?

    counts = Message.where(conversation_id: conv_ids)
                    .where(message_type: [:incoming, :outgoing])
                    .reorder(nil)
                    .group(:message_type)
                    .count
    incoming = counts['incoming'].to_i
    outgoing = counts['outgoing'].to_i
    {
      incoming: incoming,
      outgoing: outgoing,
      rate: outgoing.positive? ? (incoming.to_f / outgoing * 100).round : nil
    }
  end

  # tempo no funil: da primeira entrada em coluna até hoje (ou até a saída,
  # se o card não existe mais) + coluna atual
  def funnel_indicator(contact)
    card_ids = patient_cards(contact).map(&:id)
    return nil if card_ids.empty?

    first_entry = Crm::StageLog.where(crm_contact_id: card_ids).minimum(:entered_at)
    current = patient_cards(contact).first
    {
      current_stage: current&.stage&.name,
      current_stage_color: current&.stage&.color,
      since: current&.stage_moved_at,
      days_total: first_entry ? ((Time.current - first_entry) / 1.day).floor : nil
    }
  end
end
