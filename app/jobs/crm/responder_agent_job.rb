# Orquestra um agente RESPONDEDOR do WhatsApp em uma conversa (rodada 188).
# Disparado pelo CrmListener com espera de ~12s (anti-mensagem-picada).
#
# Dois modos, decididos na config do agente (Automações → Agentes de IA):
# - SOMBRA (padrão, Rodada 1): a IA lê a conversa e escreve numa NOTA INTERNA
#   de atividade o que TERIA respondido (mensagens, etapa, se agendaria e se a
#   vaga é válida). NADA chega ao paciente, nada é agendado, card não se move,
#   nenhuma pausa é gravada. O N8N continua atendendo e a tela "Sombra"
#   compara os dois lado a lado. Nunca gerar mensagem `outgoing` aqui: o N8N
#   roteia por incoming/outgoing e uma nota de atividade passa batida.
# - AO VIVO (rodada 193): responde de verdade, na ORDEM segura — trava a vaga →
#   confere → grava na Agenda → SÓ ENTÃO manda o "Deu certo 😊" → move o card.
#   Só dentro da JANELA da config (dias da semana em live_days + horas
#   hours_start/hours_end); fora dela o agente continua em SOMBRA, aprendendo.
#   Nessa janela o N8N tem que estar desligado — nunca os dois ao vivo.
# - FERRAMENTAS (rodada 192): ao vivo o agente também remarca/cancela/confirma
#   presença pela Agenda (Crm::ResponderTools); em sombra só simula.
class Crm::ResponderAgentJob < ApplicationJob # rubocop:disable Metrics/ClassLength
  queue_as :default

  LOG_CAP = 100
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  STATE_KEY = 'cevico_atendente_wa'.freeze
  # Rodada 2 (193): o modo ao vivo existe — a janela da config decide quando.
  # 🔒 TRAVA DO SERVIDOR (21/09, pedido dele: "ir com calma"): o modo AO VIVO só
  # existe se a variável CEVICO_RESPONDERS_LIVE=true estiver no ambiente do
  # container (EasyPanel → sistema_cevico → web e sidekiq). Sem ela, nenhum
  # atendente fala com paciente, mesmo que a tela marque "Ao vivo" — e a
  # tela mostra o cadeado. Deploy sem a variável = tudo em sombra, garantido.
  LIVE_ENABLED = ActiveModel::Type::Boolean.new.cast(ENV.fetch('CEVICO_RESPONDERS_LIVE', 'false')) == true
  DEFAULT_SHADOW_CAP = 30
  MAX_REPLIES_PER_DAY = 60

  def perform(conversation_id, trigger_message_id, agent_key)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank? || !conversation.open?

    account = conversation.account
    cfg = agent_cfg(account, agent_key)
    return unless cfg['enabled'] == true

    # anti-picada: só trabalha se esta ainda é a ÚLTIMA mensagem do paciente
    return if last_incoming_id(conversation) != trigger_message_id

    if live_mode?(cfg)
      run_live(account, conversation, cfg, agent_key, trigger_message_id)
    else
      run_shadow(account, conversation, cfg, agent_key, trigger_message_id)
    end
  end

  # ao vivo AGORA? modo live E dentro da janela (dia da semana + horas)
  def self.live_mode?(cfg)
    LIVE_ENABLED && cfg['mode'] == 'live' && within_window?(cfg)
  end

  # janela ao vivo (193): live_days = dias 0..6 (vazio = todos); horas
  # hours_start/hours_end (vazias = o dia inteiro; start > end = vira a noite,
  # ex.: 20:00 → 06:00)
  def self.within_window?(cfg, now = TZ.now) # rubocop:disable Metrics/CyclomaticComplexity
    days = Array(cfg['live_days']).map(&:to_i)
    return false if days.any? && days.exclude?(now.wday)

    start_at = cfg['hours_start'].to_s.presence
    end_at = cfg['hours_end'].to_s.presence
    return true if start_at.blank? || end_at.blank?

    hm = now.strftime('%H:%M')
    start_at <= end_at ? hm.between?(start_at, end_at) : (hm >= start_at || hm <= end_at)
  end

  # NOTA DE SOMBRA (usada pelo job e pelo Simulador): o que o agente teria
  # respondido, com os dados estruturados para a tela Sombra. Devolve se a
  # vaga que ele agendaria é válida (nil quando não agendaria).
  def self.write_shadow_note!(conversation, agent_key, result, trigger_message_id) # rubocop:disable Metrics/AbcSize
    account = conversation.account
    slot_valid = result[:agendar] ? new.send(:slot_valid?, account, result[:agendamento]) : nil
    conversation.messages.create!(
      account_id: account.id, inbox_id: conversation.inbox_id,
      message_type: :activity, private: true, content: new.send(:shadow_note, agent_key, result, slot_valid),
      additional_attributes: {
        'cevico_ia_shadow' => {
          'agent' => agent_key, 'etapa' => result[:etapa], 'mensagens' => Array(result[:mensagens]).first(3),
          'agendar' => result[:agendar] == true, 'agendamento' => (result[:agendamento] || {}),
          'slot_valid' => slot_valid, 'chamar_humano' => result[:chamar_humano] == true,
          'cancelar' => result[:cancelar] == true,
          'pausar' => result[:pausar] == true, 'leitura' => result[:leitura].to_s.truncate(300),
          # 🔧 rodada 192: o que as ferramentas fizeram/simulariam [{ferramenta, ok, resumo}]
          'acoes' => Array(result[:acoes]).first(10),
          'trigger_message_id' => trigger_message_id
        }
      }
    )
    slot_valid
  end

  private

  def live_mode?(cfg)
    self.class.live_mode?(cfg)
  end

  # ── SOMBRA ──────────────────────────────────────────────────────────────
  def run_shadow(account, conversation, cfg, agent_key, trigger_message_id) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    cap = cfg['shadow_daily_cap'].to_i.positive? ? cfg['shadow_daily_cap'].to_i : DEFAULT_SHADOW_CAP
    if shadow_cap_reached?(account, agent_key, conversation, cap)
      log_event(account, agent_key, conversation, 'teto_sombra', "teto de #{cap} conversas/dia na sombra atingido", once_per_day: true)
      return
    end

    # a mesma mensagem já ganhou nota (ex.: simulador rodou na hora e o job da fila chegou depois)
    return if shadow_note_exists?(conversation, trigger_message_id)

    result = Crm::ResponderAgentService.new(conversation: conversation, agent_key: agent_key, live: false).call
    if result[:error]
      log_event(account, agent_key, conversation, 'erro', result[:error].to_s.truncate(120))
      return
    end
    # a IA demorou e o paciente mandou mais coisa? o job da mensagem nova cuida
    return if last_incoming_id(conversation) != trigger_message_id
    return if shadow_note_exists?(conversation, trigger_message_id)

    slot_valid = self.class.write_shadow_note!(conversation, agent_key, result, trigger_message_id)
    count_shadow!(account, agent_key, conversation)
    detail = "etapa #{result[:etapa]} · #{Array(result[:mensagens]).size} msg(s)"
    detail += if result[:agendar]
                slot_valid ? ' · agendaria (vaga ✓)' : ' · agendaria (vaga ✗)'
              else
                ''
              end
    detail += ' · chamaria humano' if result[:chamar_humano]
    detail += " · 🔧 #{acoes_text(result)}" if Array(result[:acoes]).any?
    log_event(account, agent_key, conversation, 'sombra', detail.truncate(220))
  end

  # "🔧 buscou consulta: 1 encontrada (Maísa, hoje 14:00) · remarcaria p/ sáb 27/09 10:00 (simulado)"
  def acoes_text(result)
    Array(result[:acoes]).map { |a| a['resumo'].presence || a['ferramenta'] }.join(' · ')
  end

  def shadow_note(agent_key, result, slot_valid) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    name = agent_name(agent_key)
    lines = ["🕶️ Sombra · #{name} · etapa: #{result[:etapa]}"]
    lines << 'Teria respondido:'
    Array(result[:mensagens]).first(3).each_with_index { |m, i| lines << "#{i + 1}) #{m.to_s.strip}" }
    if result[:agendar]
      ag = (result[:agendamento] || {}).symbolize_keys
      unit = Crm::AgendaSlots::UNIT_LABELS[ag[:unidade]] || ag[:unidade]
      lines << "Agendaria: #{ag[:dia]} #{ag[:hora]} · #{unit} · #{ag[:nome]} · #{slot_valid ? 'vaga válida ✓' : 'vaga NÃO validou ✗'}"
    end
    flags = []
    flags << 'CANCELARIA a consulta' if result[:cancelar]
    flags << 'chamaria humano' if result[:chamar_humano]
    flags << 'encerraria (pausar)' if result[:pausar]
    lines << "Decisões: #{flags.join(' · ')}" if flags.any?
    lines << "🔧 #{acoes_text(result)}" if Array(result[:acoes]).any?
    lines << "Leitura: #{result[:leitura]}" if result[:leitura].present?
    lines << '(nota interna: nada foi enviado ao paciente)'
    lines.join("\n")
  end

  def shadow_note_exists?(conversation, trigger_message_id)
    conversation.messages.where(message_type: :activity)
                .exists?(["additional_attributes -> 'cevico_ia_shadow' ->> 'trigger_message_id' = ?", trigger_message_id.to_s])
  end

  # teto de CONVERSAS por dia na sombra (a mesma conversa conta uma vez)
  def shadow_cap_reached?(account, agent_key, conversation, cap)
    day = state_for(account, agent_key).dig('shadow_days', TZ.now.to_date.to_s) || {}
    ids = Array(day['conversation_ids'])
    return false if ids.include?(conversation.id)

    ids.size >= cap
  end

  def count_shadow!(account, agent_key, conversation)
    update_state(account, agent_key) do |state|
      days = state['shadow_days'] || {}
      today = TZ.now.to_date.to_s
      day = days[today] || { 'count' => 0, 'conversation_ids' => [] }
      day['conversation_ids'] = Array(day['conversation_ids']) + [conversation.id] unless Array(day['conversation_ids']).include?(conversation.id)
      day['count'] = day['count'].to_i + 1
      # guarda só os últimos 7 dias
      state['shadow_days'] = days.merge(today => day).sort.last(7).to_h
      state
    end
  end

  # ── AO VIVO (rodada 193; a janela já foi conferida em live_mode?) ────────
  def run_live(account, conversation, cfg, agent_key, trigger_message_id) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    state = conversation.additional_attributes&.[](STATE_KEY) || {}
    return if state['paused']

    sent_today = conversation.messages.where(message_type: :outgoing)
                             .where('created_at > ?', TZ.now.beginning_of_day)
                             .where("additional_attributes ->> 'cevico_ia_agent' = ?", agent_key).count
    if sent_today >= MAX_REPLIES_PER_DAY
      log_event(account, agent_key, conversation, 'teto_diario', 'limite de mensagens/dia atingido — pausado')
      pause!(conversation, 'teto_diario', agent_key)
      return
    end

    result = Crm::ResponderAgentService.new(conversation: conversation, agent_key: agent_key, live: true).call
    if result[:error]
      log_event(account, agent_key, conversation, 'erro', result[:error].to_s.truncate(120))
      return
    end
    return if last_incoming_id(conversation) != trigger_message_id

    # 🔧 (192) a ferramenta já remarcou ao vivo? então agendar=true do JSON é
    # eco — não tenta reservar de novo (a vaga agora é da própria consulta)
    tool_done = Array(result[:acoes]).any? { |a| a['ferramenta'] == 'remarcar_consulta' && a['ok'] }
    wants_booking = result[:agendar] && !tool_done
    # ORDEM SEGURA: agendar (trava + confere + grava) ANTES de confirmar ao paciente
    booked = wants_booking ? book!(account, conversation, result, agent_key) : nil
    if wants_booking && !booked
      # vaga não validou: não confirma; pede outra escolha em vez de sumir
      send_replies(conversation, [SLOT_TAKEN_TEXT], trigger_message_id, agent_key)
      log_event(account, agent_key, conversation, 'horario_invalido',
                "#{result.dig(:agendamento, :dia)} #{result.dig(:agendamento, :hora)} não validou")
      return
    end

    send_replies(conversation, Array(result[:mensagens]), trigger_message_id, agent_key)
    move_card_after_booking(account, conversation, cfg) if booked
    handoff_note(conversation, agent_key) if result[:chamar_humano]
    pause_reason = pause_reason_for(result, booked)
    pause!(conversation, pause_reason, agent_key) if pause_reason
    detail = "etapa #{result[:etapa]} · #{Array(result[:mensagens]).size} msg(s)"
    detail += " · 🔧 #{acoes_text(result)}" if Array(result[:acoes]).any?
    log_event(account, agent_key, conversation, booked ? 'agendou' : 'respondeu', detail.truncate(220))
  end

  SLOT_TAKEN_TEXT = 'Poxa, esse horário acabou de ser preenchido. Me diz outro período que você prefere, que eu vejo o mais próximo pra você?'.freeze

  def pause_reason_for(result, booked)
    return 'agendou' if booked
    return 'chamou_humano' if result[:chamar_humano]

    'encerrou' if result[:pausar]
  end

  # trava por conta+dia+hora+unidade → confere de novo → grava na Agenda
  def book!(account, conversation, result, agent_key) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    ag = (result[:agendamento] || {}).symbolize_keys
    date = begin
      Date.parse(ag[:dia].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    time = ag[:hora].to_s.strip
    return false if date.nil? || time.blank?

    lock_manager = Redis::LockManager.new
    lock_key = "CRM_SLOT_LOCK::#{account.id}::#{date}::#{time}::#{ag[:unidade]}"
    return false unless lock_manager.lock(lock_key, 30.seconds)

    begin
      return false unless Crm::AgendaSlots.slot_available?(account, date: date, time: time, unit: ag[:unidade])

      starts_at = Crm::AgendaSlots::TZ.parse("#{date} #{time}")
      doctor = Crm::AgendaSlots.windows(account).find { |w| w['dow'] == date.wday && w['unit'] == ag[:unidade] }&.[]('doctor')
      Crm::AppointmentRecorder.record(
        account: account,
        result: { found: true, starts_at: starts_at, name: ag[:nome], phone: ag[:telefone].presence || conversation.contact&.phone_number,
                  unit: ag[:unidade], procedure: ag[:procedimento], doctor: doctor, price: 'R$ 150',
                  notes: "Agendado pelo #{agent_name(agent_key)} (WhatsApp)" },
        contact: conversation.contact, conversation: conversation
      )
      conversation.messages.create!(
        account_id: account.id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
        content: "📅 #{agent_name(agent_key)} agendou: #{ag[:nome]} — #{starts_at.strftime('%d/%m/%Y às %H:%M')} " \
                 "(#{Crm::AgendaSlots::UNIT_LABELS[ag[:unidade]] || ag[:unidade]}). " \
                 "[📆 Ver na agenda](/app/accounts/#{account.id}/agenda?date=#{starts_at.strftime('%Y-%m-%d')})"
      )
      true
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  def send_replies(conversation, texts, trigger_message_id, agent_key)
    texts.first(3).each_with_index do |text, index|
      clean = text.to_s.tr('—', ',').strip # a regra de forma proíbe travessão; o sistema garante
      next if clean.blank?

      sleep 1.5 if index.positive?
      break if last_incoming_id(conversation) != trigger_message_id

      conversation.messages.create!(
        account_id: conversation.account_id, inbox_id: conversation.inbox_id,
        message_type: :outgoing, content: clean,
        additional_attributes: { 'cevico_ia_agent' => agent_key }
      )
    end
  end

  def move_card_after_booking(account, conversation, cfg)
    stage_id = cfg['after_booking_stage_id'].to_i
    contact = conversation.contact
    return if stage_id.zero? || contact.blank?

    stage = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).find_by(id: stage_id)
    return if stage.blank?

    card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
    return if card.blank? || card.stage_id == stage.id

    card.update!(stage_id: stage.id)
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgentJob] mover card: #{e.message}"
  end

  def handoff_note(conversation, agent_key)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :activity, private: true,
      content: "🙋 #{agent_name(agent_key)} pediu ATENDIMENTO HUMANO nesta conversa. " \
               'Responda por aqui — o agente fica pausado; mande 👍 para reativá-lo.'
    )
  end

  def pause!(conversation, reason, agent_key)
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      attrs.merge(STATE_KEY => { 'paused' => true, 'reason' => reason, 'agent' => agent_key, 'at' => Time.current.iso8601 })
    end
  end

  # ── apoio ───────────────────────────────────────────────────────────────
  def last_incoming_id(conversation)
    conversation.messages.where(message_type: :incoming, private: false).maximum(:id)
  end

  def slot_valid?(account, agendamento)
    ag = (agendamento || {}).symbolize_keys
    date = Date.parse(ag[:dia].to_s)
    Crm::AgendaSlots.slot_available?(account, date: date, time: ag[:hora].to_s.strip, unit: ag[:unidade])
  rescue ArgumentError, TypeError
    false
  end

  def agent_cfg(account, agent_key)
    (CrmSetting.find_by(account: account)&.ai_config&.dig('agents', agent_key)) || {}
  end

  def agent_name(agent_key)
    { 'atendente_agendamento' => 'Atendente de Agendamento', 'atendente_pos' => 'Atendente Pós-agendamento' }[agent_key] || agent_key
  end

  def state_for(account, agent_key)
    CrmSetting.find_by(account: account)&.ai_config&.dig("#{agent_key}_state") || {}
  end

  # mexe SÓ na chave de estado do agente, relendo a config fresca antes
  def update_state(account, agent_key)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    settings.with_lock do
      cfg = settings.ai_config || {}
      state = yield((cfg["#{agent_key}_state"] || {}).deep_dup)
      cfg["#{agent_key}_state"] = state
      settings.update!(ai_config: cfg)
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgentJob] estado: #{e.message}"
  end

  # registro de atividade do agente (visível no card, como os demais)
  def log_event(account, agent_key, conversation, type, note, once_per_day: false) # rubocop:disable Metrics/ParameterLists
    update_state(account, agent_key) do |state|
      events = Array(state['events'])
      today = TZ.now.to_date.to_s
      next state if once_per_day && events.any? { |e| e['type'] == type && e['at'].to_s.start_with?(today) }

      events.unshift({ 'at' => Time.current.iso8601, 'type' => type,
                       'conversation_id' => conversation.display_id,
                       'contact' => conversation.contact&.name.to_s.truncate(40), 'note' => note }.compact)
      state['events'] = events.first(LOG_CAP)
      state
    end
  end
end
