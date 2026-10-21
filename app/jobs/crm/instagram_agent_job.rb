# Orquestra o ATENDENTE INSTAGRAM em uma conversa:
# - disparado pelo CrmListener com espera de ~12s (anti-mensagem-picada:
#   se o paciente mandou outra mensagem nesse meio tempo, este job desiste
#   e o job da mensagem mais nova responde tudo de uma vez)
# - travas: kill switch, caixa permitida, conversa pausada, teto diário
# - envia as mensagens da IA (marcadas como do agente), agenda na Agenda
#   interna quando a IA confirmou dados + horário LIVRE, e pausa a conversa
#   quando a função termina (confirmação 😊) ou quando pede humano
class Crm::InstagramAgentJob < ApplicationJob # rubocop:disable Metrics/ClassLength
  queue_as :ai # 🚦 Rodada 6 (RESIL-1): fila da IA, cápsula própria (SIDEKIQ_AI_CONCURRENCY, config/sidekiq.yml)
  # (#100) aqui a nova tentativa do Sidekiq FICA (diferente do Atendente do
  # WhatsApp): o resgate (item 291) não cobre o Instagram, então um job que
  # morreu no meio só tem essa segunda chance. Balão repetido não acontece: o
  # already_replied? no começo do perform barra a repetição depois de um
  # balão já ter saído.

  LOG_CAP = 100
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def perform(conversation_id, trigger_message_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank? || !conversation.open?

    # 🚧 cerca dos parceiros DENTRO do job (auditoria #459): o CrmListener já
    # barra ao enfileirar; aqui é a garantia — paciente de parceiro NUNCA recebe IA
    return Crm::PartnerGuard.block!('atendente instagram', conversation: conversation) if Crm::PartnerGuard.partner_conversation?(conversation)

    state = agent_state(conversation)
    return if state['paused'] # humano assumiu / função encerrada

    # anti-picada: só responde se esta ainda é a ÚLTIMA mensagem do paciente
    return if last_incoming_id(conversation) != trigger_message_id
    # 🔁 (#100) esta mensagem já foi respondida por outro job? não chama a IA de novo
    return if Crm::ResponderAgentJob.already_replied?(conversation, trigger_message_id)

    # 🔒 (#100) trava POR CONVERSA (mesma chave do Atendente do WhatsApp): dois
    # jobs nunca respondem ao mesmo tempo — o outro volta à fila em 15 s
    with_conversation_lock(conversation, trigger_message_id) do
      reply!(conversation.account, conversation, trigger_message_id)
    end
  end

  private

  # (#100) mesmo desenho do Atendente do WhatsApp: conversa ocupada → este job
  # volta em 15 s (até 40 vezes) em vez de sair calado; cada volta refaz o
  # "ainda é a última" e o "já respondi", então não duplica balão. Aqui é
  # ainda mais importante: o resgate (item 291) só cobre as caixas do WhatsApp.
  def with_conversation_lock(conversation, trigger_message_id, &)
    lock_key = format(Crm::ResponderAgentJob::LOCK_KEY, id: conversation.id)
    return if Redis::LockManager.new.with_lock(lock_key, Crm::ResponderAgentJob::LOCK_TTL.to_i, &)

    attempt = Crm::ResponderAgentJob.busy_attempt(trigger_message_id)
    if attempt
      self.class.set(wait: Crm::ResponderAgentJob::BUSY_WAIT).perform_later(conversation.id, trigger_message_id)
      Rails.logger.info "[Crm::InstagramAgentJob] conversa #{conversation.id} ocupada por outro job — volto em " \
                        "#{Crm::ResponderAgentJob::BUSY_WAIT.to_i} s (#{attempt}/#{Crm::ResponderAgentJob::BUSY_MAX})"
    else
      Rails.logger.warn "[Crm::InstagramAgentJob] conversa #{conversation.id} ocupada há tempo demais — desisto"
    end
  end

  def last_incoming_id(conversation)
    conversation.messages.where(message_type: :incoming, private: false).maximum(:id)
  end

  # dentro da trava: teto diário → IA → agenda (se for o caso) → balões → humano / pausa → registro
  def reply!(account, conversation, trigger_message_id) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    # teto diário de segurança por conversa (dia no fuso da clínica — antes o
    # "dia" começava às 21h de Brasília por causa do UTC do servidor)
    sent_today = conversation.messages
                             .where(message_type: :outgoing)
                             .where('created_at > ?', TZ.now.beginning_of_day)
                             .where("additional_attributes ->> 'cevico_ia_agent' = 'instagram'")
                             .count
    if sent_today >= Crm::InstagramAgentService::MAX_REPLIES_PER_DAY
      log_event(account, conversation, 'teto_diario', 'limite de mensagens/dia atingido — pausado')
      pause!(conversation, 'teto_diario')
      return
    end

    read_media(conversation, trigger_message_id)
    result = Crm::InstagramAgentService.new(conversation: conversation).call
    if result[:error]
      log_event(account, conversation, 'erro', result[:error].to_s.truncate(120))
      return
    end

    # ainda é a última? (a IA demorou e o paciente mandou mais coisa)
    return if last_incoming_id(conversation) != trigger_message_id

    # 📅 auditoria 10/2026 (#103): ORDEM SEGURA, igual ao Atendente do WhatsApp —
    # trava → confere → grava na Agenda → SÓ ENTÃO o "Deu certo". Se a vaga não
    # validou, o paciente recebe o pedido de escolher outro horário (não a
    # confirmação), a tarefa ⚠️ fica para a equipe e o agente segue ativo.
    if result[:agendar]
      booked = handle_scheduling(account, conversation, result)
      if booked != true
        # sem dia/hora no JSON ninguém pegou vaga nenhuma: pede o dado que
        # falta em vez de dizer que o horário foi preenchido
        text = booked == :sem_horario ? Crm::ResponderAgentJob::MISSING_SLOT_TEXT : Crm::ResponderAgentJob::SLOT_TAKEN_TEXT
        send_replies(conversation, [text], trigger_message_id)
        return
      end
    end

    # 🧠 despedida carimbada: o robô de follow-up não cutuca depois dela (13/10)
    send_replies(conversation, Array(result[:mensagens]), trigger_message_id, encerrou: Crm::ResponderAgentJob.farewell?(result))

    handle_human_handoff(conversation) if result[:chamar_humano]

    if result[:pausar] || result[:agendar]
      pause!(conversation, result[:agendar] ? 'agendou' : 'encerrou')
    end

    log_event(account, conversation, result[:agendar] ? 'agendou' : 'respondeu',
              "etapa #{result[:etapa]} · #{Array(result[:mensagens]).size} msg(s)")
  end

  # 👂 item 340: áudio/imagem do direct viram texto antes da IA responder
  # (mesmo leitor do WhatsApp; sem chave do Gemini não faz nada). Aqui não
  # há MediaReadingJob antes: espera/lê a mensagem que disparou e as recentes.
  def read_media(conversation, trigger_message_id)
    return unless Crm::MediaReadingService.configured?(conversation.account)

    trigger = conversation.messages.find_by(id: trigger_message_id)
    Crm::MediaReadingService.settle!(trigger) if trigger&.incoming?
    Crm::MediaReadingService.read_pending!(conversation)
  rescue StandardError => e
    Rails.logger.warn "[Crm::InstagramAgentJob] leitura de mídia falhou: #{e.message}"
  end

  def agent_state(conversation)
    conversation.additional_attributes&.[]('cevico_atendente_ia') || {}
  end

  def pause!(conversation, reason)
    # merge atômico: não apaga o estado do follow-up gravado em paralelo
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      attrs.merge('cevico_atendente_ia' => { 'paused' => true, 'reason' => reason, 'at' => Time.current.iso8601 })
    end
  end

  def send_replies(conversation, texts, trigger_message_id, encerrou: false)
    # 🔁 (#100) última conferência antes de falar: alguém já respondeu esta mensagem?
    return if Crm::ResponderAgentJob.already_replied?(conversation, trigger_message_id)

    attrs = { 'cevico_ia_agent' => 'instagram' }
    attrs['cevico_encerrou'] = true if encerrou # carimbo lido pelo Crm::FollowupClosure

    texts.first(3).each_with_index do |text, index|
      next if text.blank?

      sleep 1.5 if index.positive? # respiro entre mensagens (humanização)
      # o paciente mandou algo novo no meio do envio? para de responder — o job
      # da mensagem mais nova cuida do resto (evita resposta picada/atropelada)
      break if conversation.messages.where(message_type: :incoming, private: false).maximum(:id) != trigger_message_id

      conversation.messages.create!(
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        message_type: :outgoing,
        content: text,
        additional_attributes: attrs
      )
    end
  end

  # devolve true quando a consulta foi gravada na Agenda; :sem_horario quando a
  # IA não trouxe dia/hora; false quando a vaga não validou ou a Agenda não
  # gravou (nos dois últimos o chamador NÃO confirma ao paciente)
  def handle_scheduling(account, conversation, result) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    ag = (result[:agendamento] || {}).symbolize_keys
    date = begin
      Date.parse(ag[:dia].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    time = ag[:hora].to_s.strip

    if date.nil? || time.blank?
      open_review_task(account, conversation, ag, 'sem dia/hora')
      log_event(account, conversation, 'horario_invalido', "#{ag[:dia]} #{ag[:hora]} sem dia/hora — tarefa criada")
      return :sem_horario
    end

    # TRAVA do horário: a checagem de disponibilidade e o registro acontecem
    # dentro da mesma trava (por conta+dia+hora+unidade), senão duas conversas
    # confirmando ao mesmo tempo marcavam o MESMO horário (TOCTOU).
    lock_manager = Redis::LockManager.new
    lock_key = "CRM_SLOT_LOCK::#{account.id}::#{date}::#{time}::#{ag[:unidade]}"
    slot_locked = lock_manager.lock(lock_key, 30.seconds)

    if !slot_locked || !Crm::AgendaSlots.slot_available?(account, date: date, time: time, unit: ag[:unidade])
      # horário inválido/ocupado/em disputa (a IA não deveria, mas o sistema
      # confere): tarefa de revisão em vez de agendar errado.
      open_review_task(account, conversation, ag, 'horário ocupado ou inválido')
      log_event(account, conversation, 'horario_invalido', "#{ag[:dia]} #{ag[:hora]} não validou — tarefa criada")
      lock_manager.unlock(lock_key) if slot_locked
      return false
    end

    outcome = nil
    begin
      starts_at = Crm::AgendaSlots::TZ.parse("#{date} #{time}")
      doctor = Crm::AgendaSlots.doctor_at(account, date, time, ag[:unidade]) # item 311: o médico da faixa do horário

      outcome = Crm::AppointmentRecorder.record(
        account: account,
        result: { found: true, starts_at: starts_at, name: ag[:nome], phone: ag[:telefone],
                  # 💰 (#132) sem preço fixo: o valor da consulta vem do pré-configurado (item 324)
                  unit: ag[:unidade], procedure: ag[:procedimento], doctor: doctor,
                  notes: 'Agendado pelo Atendente Instagram (direct)' },
        contact: conversation.contact,
        conversation: conversation
      )
    ensure
      lock_manager.unlock(lock_key)
    end

    # a Agenda não gravou (:skipped — conta sem criador, por exemplo): sem
    # consulta na Agenda não existe "Deu certo"
    unless %i[created rescheduled already].include?(outcome)
      open_review_task(account, conversation, ag, "a Agenda não gravou (#{outcome})")
      log_event(account, conversation, 'erro', "#{ag[:dia]} #{ag[:hora]} não entrou na Agenda (#{outcome}) — tarefa criada")
      return false
    end

    update_contact_phone(conversation.contact, ag[:telefone])

    conversation.messages.create!(
      account_id: account.id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
      content: "📅 Atendente Instagram agendou: #{ag[:nome]} — #{starts_at.strftime('%d/%m/%Y às %H:%M')} " \
               "(#{Crm::SegmentoConta.unit_label(account, ag[:unidade])}). Confirmação oficial segue pelo WhatsApp. " \
               "[📆 Ver na agenda](/app/accounts/#{account.id}/agenda?date=#{starts_at.strftime('%Y-%m-%d')})"
    )
    true
  end

  # tarefa de revisão para a equipe quando o agendamento não entrou na Agenda.
  # 🔐 achado #148: nasce como CARD do quadro (tipo 'Atendimento', sem
  # data/unidade — a unidade fica no texto) e carimbada 'robo', senão
  # ninguém vê (Tarefas, Meu Painel e Agenda escondem 'consulta' sem data).
  def open_review_task(account, conversation, booking, reason)
    Crm::Stamp.with(via: 'robo') do
      account.tasks.create!(
        title: "⚠️ Confirmar consulta (Instagram): #{booking[:nome].presence || 'Paciente'}",
        description: "O Atendente Instagram tentou agendar e o sistema não validou (#{reason}). O paciente NÃO recebeu " \
                     "confirmação; pedimos a ele outro horário ou o dado que faltou.\n" \
                     "Dados: #{booking.map { |k, v| "#{k}: #{v}" }.join(' · ')}\nConversa ##{conversation.display_id}",
        phone: booking[:telefone], contact: conversation.contact,
        task_type: 'Atendimento', priority: :high, status: :todo,
        creator: account.administrators.first || account.users.first,
        assignee: Crm::TaskOwner.resolve(account, contact: conversation.contact, task_type: 'consulta')
      )
    end
  end

  # telefone captado no direct → contato ganha o número (ponte para o
  # WhatsApp assumir as confirmações oficiais)
  def update_contact_phone(contact, phone)
    return if contact.blank? || phone.blank? || contact.phone_number.present?

    digits = phone.to_s.gsub(/\D/, '')
    return if digits.length < 10

    e164 = digits.start_with?('55') ? "+#{digits}" : "+55#{digits}"
    contact.update(phone_number: e164)
  rescue StandardError => e
    Rails.logger.warn "[Crm::InstagramAgent] telefone: #{e.message}"
  end

  def handle_human_handoff(conversation)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :activity, private: true,
      content: '🙋 Atendente Instagram pediu ATENDIMENTO HUMANO nesta conversa (urgência/caso complexo). ' \
               'Responda por aqui — o agente ficará pausado; mande 👍 para reativá-lo.'
    )
    pause!(conversation, 'chamou_humano')
  end

  # registro de atividade do agente (visível no card, como os demais).
  # 🔒 Rodada 4 da auditoria (RESIL-3): pelo Crm::AgentState, que grava sob a
  # trava da linha relendo a config fresca — antes este método "lia → alterava
  # → gravava" o ai_config inteiro e podia apagar o que o admin ou outro job
  # acabou de salvar (chave da API, agente ligado/desligado, outros estados)
  def log_event(account, conversation, type, note)
    Crm::AgentState.log(account, 'instagram', type, note,
                        contact: conversation.contact&.name, conversation_id: conversation.display_id)
  end
end
