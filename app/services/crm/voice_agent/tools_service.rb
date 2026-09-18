# Executa uma ferramenta chamada pela assistente virtual no meio da
# ligação (webhook /tools/<nome>) e devolve um Hash com chaves em pt-BR —
# a IA lê o JSON e fala. Datas/horários vêm com um campo "falado" pronto.
# Toda chamada faz o upsert da Crm::Call (status accepted) e, quando há
# conversa na caixa da clínica, deixa uma nota privada curta do que foi
# feito. Reusa Task.match_contact, Crm::AgendaSlots, Crm::AppointmentRecorder,
# Crm::Calls::ConversationFinder e Crm::SendTemplateService.
class Crm::VoiceAgent::ToolsService # rubocop:disable Metrics/ClassLength
  TZ = Crm::AgendaSlots::TZ
  MAX_SLOTS = 6
  RESULTS = { created: 'marcada', rescheduled: 'remarcada', already: 'ja_existia', skipped: 'nao_foi_possivel' }.freeze
  ADDRESSES = {
    'paulista' => 'Av. Paulista, 1499 – 9º andar (melhor acesso: Alameda Casa Branca, 35), próximo à estação Trianon-MASP',
    'tatuape' => 'R. Serra de Botucatu, 880 – 4º andar, próximo à estação Carrão'
  }.freeze

  attr_reader :account, :tool, :params, :conversation_id

  def initialize(account:, tool:, params:, conversation_id: nil)
    @account = account
    @tool = tool.to_s
    @params = (params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h).deep_stringify_keys
    @conversation_id = conversation_id.presence || @params['conversa_id'].presence
  end

  def perform
    return { ok: false, erro: "Ferramenta desconhecida: #{tool}" } unless Crm::VoiceAgent::Settings::TOOL_NAMES.include?(tool)

    upsert_call
    send(:"tool_#{tool}")
  rescue StandardError => e
    Rails.logger.error("[CEVICO voice] ferramenta #{tool} (conta #{account.id}): #{e.class}: #{e.message}")
    { ok: false, erro: e.message }
  end

  private

  def settings
    @settings ||= Crm::VoiceAgent::Settings.new(account)
  end

  # ── quem está na linha ────────────────────────────────────────────────────
  def caller_digits
    @caller_digits ||= params['telefone'].to_s.gsub(/\D/, '')
  end

  # telefone da conversa: quem ligou; senão o do contato da campanha
  def wa_id
    @wa_id ||= caller_digits.presence || contact&.phone_number.to_s.gsub(/\D/, '')
  end

  def campaign_contact
    return @campaign_contact if defined?(@campaign_contact)

    @campaign_contact = Crm::CallCampaignContact.for_conversation(account, conversation_id)
  end

  def contact
    return @contact if defined?(@contact)

    @contact = campaign_contact&.contact || (caller_digits.length >= 8 ? Task.match_contact(account, caller_digits) : nil)
  end

  # ── a ligação (Crm::Call) ─────────────────────────────────────────────────
  def call
    return @call if defined?(@call)

    @call = conversation_id.present? ? (Crm::Call.find_by(account_id: account.id, provider_call_id: conversation_id) || build_call) : nil
  end

  def build_call
    inbox = settings.call_inbox
    return nil unless inbox

    finder = conversation_finder(inbox)
    Crm::Call.new(
      account: account, inbox: inbox, contact: finder&.contact || contact, conversation: finder&.conversation,
      meta_call_id: "el:#{conversation_id}", provider: 'elevenlabs', provider_call_id: conversation_id, handled_by: 'ai',
      direction: campaign_contact ? :outbound : :inbound, campaign_id: campaign_contact&.call_campaign_id,
      status: :accepted, wa_id: wa_id.presence, display_name: contact&.name
    )
  end

  # paciente + conversa na caixa (só com telefone conhecido)
  def conversation_finder(inbox)
    return nil if wa_id.length < 8

    Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: wa_id, name: contact&.name, contact: contact)
  end

  def upsert_call
    return unless call

    call.assign_attributes(started_at: call.started_at || Time.current, answered_at: call.answered_at || Time.current)
    call.status = :accepted if call.ringing?
    call.contact ||= contact
    call.save! if call.changed?
    link_campaign_call
  end

  def link_campaign_call
    return unless campaign_contact && campaign_contact.call_id.nil?

    campaign_contact.update!(call_id: call.id)
  end

  def conversation
    call&.conversation
  end

  def note(text)
    return unless conversation

    conversation.messages.create!(account_id: account.id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
                                  content: "🤖 #{text}")
  rescue StandardError => e
    Rails.logger.warn("[CEVICO voice] nota não gravada: #{e.message}")
  end

  # ── ferramentas ───────────────────────────────────────────────────────────
  def tool_buscar_paciente
    return { encontrado: false, telefone: caller_digits, nome: '', primeiro_nome: '', proxima_consulta: '' } unless contact

    future = future_appointment
    { encontrado: true, nome: contact.name.to_s, primeiro_nome: first_name(contact.name), telefone: contact.phone_number.to_s,
      proxima_consulta: future ? appointment_spoken(future) : '', etapa_funil: funnel_stage.to_s, unidade_preferida: preferred_unit.to_s }
  end

  def tool_minha_consulta
    future = future_appointment
    return { encontrada: false, quando: '', mensagem: 'Nenhuma consulta futura marcada para este telefone.' } unless future

    due = future.due_at.in_time_zone(TZ)
    { encontrada: true, quando: appointment_spoken(future), falado: appointment_spoken(future), data: due.strftime('%Y-%m-%d'),
      dia: "#{Crm::AgendaSlots::WEEKDAYS[due.wday]} #{due.strftime('%d/%m')}", hora: due.strftime('%H:%M'),
      unidade: unit_label(future.unit), medico: future.doctor.to_s, procedimento: future.procedure.to_s }
  end

  def tool_horarios_livres
    slots = filtered_slots.first(MAX_SLOTS).map { |slot| slot_payload(slot) }
    texto = if slots.empty?
              'Nenhum horário livre nos próximos dias. Diga que a equipe vai verificar e retornar pelo WhatsApp.'
            else
              slots.pluck(:falado).join('; ')
            end
    { horarios: slots, texto: texto }
  end

  # 2 por janela/dia para espalhar as opções pelos dias; filtros da IA por cima
  def filtered_slots
    days = params['dias'].to_i.positive? ? params['dias'].to_i.clamp(1, 30) : 7
    Crm::AgendaSlots.free_slots(account, days: days, per_window: 2).select { |slot| slot_matches?(slot) }
  end

  def slot_matches?(slot)
    (wanted_unit.nil? || slot[:unit] == wanted_unit) && (wanted_doctor.nil? || slot[:doctor] == wanted_doctor) &&
      period_match?(slot[:time], params['periodo'])
  end

  def wanted_unit
    @wanted_unit ||= normalize_unit(params['unidade'])
  end

  def wanted_doctor
    @wanted_doctor ||= params['medico'].present? ? Crm::DoctorNames.canonical(params['medico']) : nil
  end

  def period_match?(time, period)
    hour = time.to_s.split(':').first.to_i
    case period.to_s.downcase
    when 'manha', 'manhã' then hour < 12
    when 'tarde' then hour >= 12
    else true
    end
  end

  def slot_payload(slot)
    date = slot[:date]
    { data: date.strftime('%Y-%m-%d'), dia: "#{Crm::AgendaSlots::WEEKDAYS[date.wday]} #{date.strftime('%d/%m')}", hora: slot[:time],
      unidade: unit_label(slot[:unit]), unidade_codigo: slot[:unit], medico: slot[:doctor],
      falado: spoken_slot(date, slot[:time], slot[:unit], slot[:doctor]) }
  end

  # marca a consulta na Agenda interna (mesma trava/validação do Atendente Instagram)
  def tool_marcar_consulta
    date = safe_date(params['data'])
    time = params['hora'].to_s.strip
    unit = normalize_unit(params['unidade'])
    invalid = date.nil? || !time.match?(/\A\d{2}:\d{2}\z/) || unit.nil?
    return { ok: false, resultado: 'dados_invalidos', mensagem: 'Preciso de data (AAAA-MM-DD), hora (HH:MM) e unidade.' } if invalid

    with_slot_lock(date, time, unit) do
      next unavailable unless Crm::AgendaSlots.slot_available?(account, date: date, time: time, unit: unit)

      record_appointment(date, time, unit)
    end
  end

  # TRAVA por conta+dia+hora+unidade: duas ligações confirmando ao mesmo tempo
  # não marcam o MESMO horário (TOCTOU) — igual ao instagram_agent_job
  def with_slot_lock(date, time, unit)
    lock_manager = Redis::LockManager.new
    lock_key = "CRM_SLOT_LOCK::#{account.id}::#{date}::#{time}::#{unit}"
    return unavailable unless lock_manager.lock(lock_key, 30.seconds)

    begin
      yield
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  def unavailable
    { ok: false, resultado: 'horario_indisponivel', mensagem: 'Esse horário acabou de ser ocupado. Ofereça outros dois horários.' }
  end

  def record_appointment(date, time, unit)
    doctor = booking_doctor(date, unit)
    name = params['nome'].to_s.strip.presence || contact&.name.presence || 'Paciente'
    result = appointment_result(TZ.parse("#{date} #{time}"), name, unit, doctor)
    outcome = Crm::AppointmentRecorder.record(account: account, result: result, contact: contact, conversation: conversation)
    resultado = RESULTS[outcome] || outcome.to_s
    @appointment = { date: date, time: time, unit: unit, doctor: doctor, name: name }
    note("Assistente virtual #{resultado == 'remarcada' ? 'remarcou' : 'marcou'} consulta: #{name} — " \
         "#{result[:starts_at].strftime('%d/%m/%Y às %H:%M')} (#{unit_label(unit)})#{doctor && " · #{doctor}"}")
    booking_response(resultado, date, time, unit, doctor)
  end

  # médico pedido (nome oficial) ou o da janela daquele dia/unidade
  def booking_doctor(date, unit)
    Crm::DoctorNames.canonical(params['medico']) ||
      Crm::AgendaSlots.windows(account).find { |w| w['dow'] == date.wday && w['unit'] == unit }&.dig('doctor')
  end

  # hash no formato que o Crm::AppointmentRecorder espera
  def appointment_result(starts_at, name, unit, doctor)
    phone = params['telefone_informado'].to_s.gsub(/\D/, '').presence || wa_id
    { found: true, starts_at: starts_at, name: name, phone: phone.present? ? "+#{phone}" : nil, unit: unit, doctor: doctor,
      procedure: params['procedimento'].to_s.strip.presence,
      notes: ['Marcada pela assistente virtual (ligação)', params['observacoes'].to_s.strip.presence].compact.join("\n") }
  end

  def booking_response(resultado, date, time, unit, doctor)
    { ok: %w[marcada remarcada ja_existia].include?(resultado), resultado: resultado, mensagem: result_message(resultado),
      consulta: { data: date.strftime('%Y-%m-%d'), hora: time, unidade: unit_label(unit), medico: doctor.to_s,
                  falado: spoken_slot(date, time, unit, doctor) } }
  end

  def result_message(resultado)
    { 'marcada' => 'Consulta marcada. Confirme em voz alta e ofereça a confirmação pelo WhatsApp.',
      'remarcada' => 'A consulta anterior do paciente foi movida para este horário.',
      'ja_existia' => 'O paciente já tinha exatamente esta consulta marcada.' }[resultado] ||
      'Não foi possível marcar. Diga que a equipe vai confirmar pelo WhatsApp.'
  end

  # mensagem pelo WhatsApp da clínica: texto livre na janela de 24h; senão o
  # modelo configurado; senão explica para a IA
  def tool_enviar_whatsapp
    inbox = settings.handoff_inbox
    return { ok: false, motivo: 'caixa não configurada' } unless inbox
    return { ok: false, motivo: 'paciente sem telefone' } if wa_id.length < 8

    text = whatsapp_text(params['tipo'].to_s)
    return { ok: false, motivo: 'tipo desconhecido' } if text.blank?

    finder = Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: wa_id, name: contact&.name, contact: contact)
    return send_text(inbox, finder.conversation, text) if finder.conversation.can_reply?
    return send_template(inbox, finder.contact, text) if settings.handoff_template_params.present?

    { ok: false, motivo: 'janela de 24h fechada e sem modelo configurado' }
  end

  def send_text(inbox, target, text)
    target.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: text,
                            additional_attributes: { 'cevico_ia_agent' => 'voice' })
    note("Assistente virtual enviou WhatsApp (#{params['tipo']}): #{text.truncate(120)}")
    { ok: true, motivo: 'enviado' }
  end

  def send_template(inbox, target_contact, preview)
    source = Crm::TemplateSource.new(account, inbox, account.administrators.first,
                                     settings.handoff_template_params, preview, 'Assistente virtual')
    sent = Crm::SendTemplateService.new(source: source, contact: target_contact).perform
    return { ok: false, motivo: 'o modelo não pôde ser enviado' } if sent.nil?

    note('Assistente virtual abriu conversa pelo modelo de continuidade (janela de 24h fechada)')
    { ok: true, motivo: 'modelo enviado' }
  end

  def whatsapp_text(kind)
    name = first_name(params['nome'].presence || contact&.name)
    hello = name.present? ? "Olá #{name}!" : 'Olá!'
    case kind
    when 'confirmacao' then confirmation_text(hello)
    when 'continuar' then "#{hello} Aqui é a CEVICO. Como combinamos na ligação, vamos continuar por aqui 😊 Me conta o que você precisa."
    when 'resumo' then params['texto'].to_s.strip.presence
    end
  end

  def confirmation_text(hello)
    appt = @appointment || future_appointment_hash
    return "#{hello} Aqui é a CEVICO. Qualquer dúvida sobre a sua consulta é só responder aqui." unless appt

    when_text = "#{Crm::AgendaSlots::WEEKDAYS[appt[:date].wday]} #{appt[:date].strftime('%d/%m')} às #{appt[:time]}"
    parts = [when_text, unit_label(appt[:unit]), appt[:doctor].presence].compact.join(' · ')
    "#{hello} Confirmando sua consulta: #{parts}. Endereço: #{ADDRESSES[appt[:unit]] || 'confirme com a equipe'}. " \
      'Leve um documento com foto e suspenda lentes de contato 72h antes. Qualquer dúvida é só responder aqui.'
  end

  def future_appointment_hash
    future = future_appointment
    return nil unless future

    due = future.due_at.in_time_zone(TZ)
    { date: due.to_date, time: due.strftime('%H:%M'), unit: future.unit.to_s, doctor: future.doctor }
  end

  # resultado + resumo na ligação e no contato da campanha
  def tool_registrar_resultado
    resultado = params['resultado'].to_s.strip
    return { ok: false, erro: "Resultado desconhecido: #{resultado}" } unless Crm::Call::OUTCOME_LABELS.key?(resultado)

    summary = params['resumo'].to_s.strip.presence
    call&.update!(outcome: resultado, summary: summary || call.summary)
    campaign_contact&.update!(outcome: resultado)
    note("Assistente virtual registrou: #{Crm::Call::OUTCOME_LABELS[resultado]}#{summary && " — #{summary}"}")
    { ok: true }
  end

  # ── apoio ─────────────────────────────────────────────────────────────────
  def future_appointment
    return @future_appointment if defined?(@future_appointment)

    @future_appointment = wa_id.length >= 8 || contact ? Crm::AppointmentRecorder.future_appointment(account, wa_id, nil, contact) : nil
  end

  def appointment_spoken(task)
    due = task.due_at.in_time_zone(TZ)
    spoken_slot(due.to_date, due.strftime('%H:%M'), task.unit, task.doctor)
  end

  def spoken_slot(date, time, unit, doctor)
    parts = ["#{Crm::VoiceAgent::Script.spoken_date(date)}, às #{Crm::VoiceAgent::Script.spoken_time(time)}"]
    parts << "na unidade #{unit_label(unit)}" if unit.present?
    parts << "com #{Crm::VoiceAgent::Script.spoken_doctor(doctor)}" if doctor.present?
    parts.join(', ')
  end

  def funnel_stage
    Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: account.id }, contact_id: contact.id).first&.stage&.name
  end

  def preferred_unit
    unit = Task.for_patient(account, contact).where(task_type: 'consulta').order(due_at: :desc).pick(:unit)
    unit.present? ? unit_label(unit) : nil
  end

  def unit_label(unit)
    Crm::AgendaSlots::UNIT_LABELS[unit.to_s] || unit.to_s
  end

  # "Tatuapé", "paulista", "Av. Paulista" → código da unidade (nil se desconhecida)
  def normalize_unit(raw)
    text = I18n.transliterate(raw.to_s).downcase
    return 'tatuape' if text.include?('tatuape')
    return 'paulista' if text.include?('paulista')

    nil
  end

  def first_name(name)
    name.to_s.strip.split(/\s+/).first.to_s
  end

  def safe_date(raw)
    Date.iso8601(raw.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
