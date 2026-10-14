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
#   confere → grava na Agenda → SÓ ENTÃO manda o "Deu certo" → etiqueta e
#   move o card (Crm::BookingSideEffects). Item 200 (22/09): o agente RODA
#   SOLTO — agendar não pausa mais; só chamar_humano pausa (👍 reativa).
#   Só dentro da JANELA da config (dias da semana em live_days + horas
#   hours_start/hours_end); fora dela o agente continua em SOMBRA, aprendendo.
#   Nessa janela o N8N tem que estar desligado — nunca os dois ao vivo.
# - FERRAMENTAS (rodada 192): ao vivo o agente também remarca/cancela/confirma
#   presença pela Agenda (Crm::ResponderTools); em sombra só simula.
class Crm::ResponderAgentJob < ApplicationJob # rubocop:disable Metrics/ClassLength
  queue_as :ai # 🚦 Rodada 6 (RESIL-1): fila da IA, cápsula própria (SIDEKIQ_AI_CONCURRENCY, config/sidekiq.yml)
  # 🔁 auditoria 10/2026 (#100): SEM nova tentativa automática do Sidekiq. Se um
  # erro escapasse DEPOIS de um balão já ter saído, o Sidekiq rodava o job
  # inteiro de novo: nova chamada da IA e balões repetidos (cada um cobrado
  # pela Meta). O erro da chamada da IA já tem a própria nova tentativa
  # (retry_later, item 291) e o resgate cobre o job que morreu no meio.
  # retry: 0 (e não false): nenhuma repetição, mas o job que estourou erro
  # aparece em "Mortos" no painel do Sidekiq — com false ele sumia sem rastro.
  sidekiq_options retry: 0

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
  # 🔒 auditoria (#100): trava POR CONVERSA — só um job responde por vez.
  # TTL maior que o PIOR caso de um job: até 6 chamadas da IA (MAX_TOOL_ROUNDS + 1)
  # × 90 s × 2 tentativas do cliente (Crm::ResponderAgentService#client) = 18 min,
  # mais a leitura de mídia (4 anexos × 90 s = 6 min) → 24 min; 30 min dá folga.
  # (item 340: a espera pela leitura da mensagem que disparou soma ~25 s + 1 leitura)
  LOCK_KEY = 'cevico:responder:conv:%<id>s'.freeze
  LOCK_TTL = 30.minutes
  # conversa ocupada por outro job: este NÃO sai — volta à fila em 15 s, até 40
  # vezes (10 min, cobre a leitura de mídia). Ver with_conversation_lock.
  BUSY_WAIT = 15.seconds
  BUSY_MAX = 40
  BUSY_KEY = 'cevico:responder:busy:%<id>s'.freeze
  # balões que contam como "já respondi": só os atendentes de TEXTO. O Agente
  # de Ligação também grava WhatsApp com cevico_ia_agent = 'voice' e não pode
  # calar o Atendente (a mensagem do paciente ficaria sem resposta).
  TEXT_AGENT_KEYS = (CrmListener::RESPONDER_KEYS + %w[instagram]).freeze

  def perform(conversation_id, trigger_message_id, agent_key)
    conversation = Conversation.find_by(id: conversation_id)
    return unless workable?(conversation)

    # 🚧 cerca dos parceiros DENTRO do job (auditoria #63/#98/#253/#459): o
    # CrmListener já barra na hora de enfileirar, mas o resgate (item 291) e
    # qualquer outro caminho chegam aqui — paciente de parceiro NUNCA recebe IA
    return Crm::PartnerGuard.block!("atendente #{agent_key}", conversation: conversation) if Crm::PartnerGuard.partner_conversation?(conversation)

    account = conversation.account
    cfg = agent_cfg(account, agent_key)
    return unless cfg['enabled'] == true

    # anti-picada: só trabalha se esta ainda é a ÚLTIMA mensagem do paciente
    return if last_incoming_id(conversation) != trigger_message_id

    # 🔒 (#100) só UM job por conversa de cada vez (o outro volta à fila em 15 s)
    with_conversation_lock(conversation, trigger_message_id, agent_key) do
      # 👂🖼️ item 204: áudio/imagem ainda não lidos (o MediaReadingJob costuma
      # chegar antes; aqui é a garantia) — o Atendente responde ao CONTEÚDO
      read_pending_media(account, conversation, agent_key, trigger_message_id)

      if live_now?(cfg, conversation)
        run_live(account, conversation, cfg, agent_key, trigger_message_id)
      else
        run_shadow(account, conversation, cfg, agent_key, trigger_message_id)
      end
    end
  end

  # conversa aberta e de paciente: o celular de teste da jornada (R3 #416) não
  # recebe IA — se a pessoa da equipe responder ao teste, a IA não entra
  def workable?(conversation)
    conversation.present? && conversation.open? && !Crm::Journey::TestContact.test_contact?(conversation.contact)
  end

  # (#100) a mensagem do paciente JÁ ganhou balão do agente? (outro job da
  # mesma mensagem passou antes — resgate, fila repetida) → já foi respondida.
  # O Atendente Instagram usa a mesma conferência.
  def self.already_replied?(conversation, trigger_message_id)
    conversation.messages.where(message_type: :outgoing).where('id > ?', trigger_message_id.to_i)
                .exists?(["additional_attributes ->> 'cevico_ia_agent' IN (?)", TEXT_AGENT_KEYS])
  end

  # (#100) conversa ocupada: conta a tentativa desta mensagem (chave por
  # mensagem, some em 1 h) e devolve o nº dela — ou nil quando passou do teto
  # (BUSY_MAX), para nunca virar laço. O Atendente Instagram usa o mesmo.
  def self.busy_attempt(trigger_message_id)
    key = format(BUSY_KEY, id: trigger_message_id)
    attempt = Redis::Alfred.incr(key).to_i
    Redis::Alfred.expire(key, 1.hour.to_i)
    attempt <= BUSY_MAX ? attempt : nil
  end

  # ao vivo AGORA? modo live E dentro da janela (dia da semana + horas)
  def self.live_mode?(cfg)
    LIVE_ENABLED && cfg['mode'] == 'live' && within_window?(cfg)
  end

  # janela ao vivo (193): live_days = dias 0..6 (vazio = todos); horas
  # hours_start/hours_end (vazias = o dia inteiro; start > end = vira a noite,
  # ex.: 20:00 → 06:00). Regra compartilhada em Crm::AgentWindow (195: o
  # Agente de Ligação usa a mesma).
  def self.within_window?(cfg, now = TZ.now)
    Crm::AgentWindow.within?(cfg, now)
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

  # 🧪 auditoria (#212): conversa SIMULADA (rake cevico:wa_agent_simulate,
  # simulador da tela) NUNCA roda ao vivo — mesmo com o agente ao vivo na
  # janela, fica na sombra: nenhum balão sai para número nenhum
  def live_now?(cfg, conversation)
    live_mode?(cfg) && !Crm::AgentSimulator.simulated?(conversation)
  end

  # 🔒 auditoria (#100): trava POR CONVERSA. Dois jobs — o original lento lendo
  # áudios e o resgate, uma fila repetida, ou a 2ª mensagem do paciente
  # enquanto a IA pensa na 1ª — nunca respondem ao mesmo tempo. Se a conversa
  # está ocupada, este job NÃO sai: volta à fila em 15 s (até 40 vezes), e cada
  # volta refaz o "ainda é a última" e o "já respondi" — por isso não duplica
  # balão. Sair calado deixava o paciente sem resposta: o job novo sumia e o
  # antigo descartava a resposta por não ser mais a última mensagem.
  def with_conversation_lock(conversation, trigger_message_id, agent_key, &)
    lock_key = format(LOCK_KEY, id: conversation.id)
    return if Redis::LockManager.new.with_lock(lock_key, LOCK_TTL.to_i, &)

    attempt = self.class.busy_attempt(trigger_message_id)
    if attempt
      self.class.set(wait: BUSY_WAIT).perform_later(conversation.id, trigger_message_id, agent_key)
      Rails.logger.info "[Crm::ResponderAgentJob] conversa #{conversation.id} ocupada por outro job — volto em #{BUSY_WAIT.to_i} s " \
                        "(#{attempt}/#{BUSY_MAX})"
    else
      Rails.logger.warn "[Crm::ResponderAgentJob] conversa #{conversation.id} ocupada há mais de #{(BUSY_WAIT * BUSY_MAX).to_i / 60} min " \
                        '— desisto (o resgate cuida)'
    end
  end

  # 🔁 item 340: antes de responder, ESPERA (até 25 s) a leitura dos
  # áudios/imagens da mensagem que disparou este job — e lê na hora o que não
  # começou ou falhou de forma passageira. Antes, o áudio ainda subindo ou
  # recém-falhado virava "[áudio sem transcrição]" e a IA calava. Cabe com
  # folga na trava da conversa (LOCK_TTL 30 min).
  def read_pending_media(account, conversation, agent_key, trigger_message_id = nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    trigger = trigger_message_id && conversation.messages.find_by(id: trigger_message_id)
    done = trigger&.incoming? ? Crm::MediaReadingService.settle!(trigger) : {}
    done = Crm::MediaReadingService.read_pending!(conversation).merge(done) { |_kind, a, b| a + b }
    return if done.blank?

    parts = []
    parts << "#{done['audio']} áudio(s) transcrito(s)" if done['audio'].to_i.positive?
    parts << "#{done['image']} imagem(ns) lida(s)" if done['image'].to_i.positive?
    log_event(account, agent_key, conversation, 'midia', parts.join(' · ')) if parts.any?
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgentJob] leitura de mídia falhou: #{e.message}"
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
    urgent_outside_window!(account, conversation, cfg, agent_key, result)
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
    if state['paused']
      # 🚨 auditoria 10/2026 (#443): pausado por URGÊNCIA clínica e o paciente
      # escreveu de novo ("piorou", "e agora?") sem ninguém da equipe ter
      # respondido: não fica em silêncio — repete a orientação de pronto
      # atendimento (texto fixo, sem IA, no máximo uma vez por hora)
      urgent_orientation!(account, conversation, trigger_message_id, agent_key, state) if state['urgente']
      return
    end
    # 🔁 (#100) esta mensagem já foi respondida por outro job? não chama a IA de novo
    return if self.class.already_replied?(conversation, trigger_message_id)

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
      attempt = retry_later(conversation, trigger_message_id, agent_key, result[:error])
      note = result[:error].to_s.truncate(120)
      note = "#{note} · vou tentar de novo (#{attempt}/#{RETRY_WAITS.size})" if attempt
      log_event(account, agent_key, conversation, 'erro', note)
      return
    end
    return if last_incoming_id(conversation) != trigger_message_id

    # 🔧 (192) a ferramenta já remarcou ao vivo? então agendar=true do JSON é
    # eco — não tenta reservar de novo (a vaga agora é da própria consulta)
    tool_done = Array(result[:acoes]).any? { |a| a['ferramenta'] == 'remarcar_consulta' && a['ok'] }
    wants_booking = result[:agendar] && !tool_done
    # ORDEM SEGURA: agendar (trava + confere + grava) ANTES de confirmar ao paciente
    booked = wants_booking ? book!(account, conversation, result, agent_key, cfg) : nil
    if wants_booking && booked != true
      # vaga não validou: não confirma; pede outra escolha em vez de sumir.
      # Sem dia/hora no JSON ninguém pegou vaga nenhuma: pede o dado que falta
      send_replies(conversation, [booked == :sem_horario ? MISSING_SLOT_TEXT : SLOT_TAKEN_TEXT], trigger_message_id, agent_key)
      log_event(account, agent_key, conversation, 'horario_invalido',
                "#{result.dig(:agendamento, :dia)} #{result.dig(:agendamento, :hora)} não validou")
      return
    end

    # 🚫 auditoria 10/2026 (#457): cancelar=true no JSON sem a IA ter chamado a
    # ferramenta não cancelava nada — o paciente ouvia "sua consulta será
    # cancelada" e a consulta seguia na Agenda (lembrete pago, vaga presa, falta).
    # ORDEM SEGURA, como no agendar: cancela ANTES de falar; se não der (sem
    # consulta própria), abre tarefa para a equipe e fala a verdade.
    if result[:cancelar] && !cancel_handled?(result)
      outcome = cancel_own_appointment!(conversation, result, agent_key)
      if outcome != :cancelada
        send_replies(conversation, [outcome == :tarefa ? CANCEL_PENDING_TEXT : CANCEL_FAILED_TEXT], trigger_message_id, agent_key)
        log_event(account, agent_key, conversation, outcome == :tarefa ? 'cancelar_pendente' : 'erro', CANCEL_EVENT_NOTES[outcome])
        # a equipe assume daqui (senão a próxima resposta do paciente repete o pedido)
        hand_over!(conversation, result, agent_key, task_opened: outcome == :tarefa)
        return
      end
    end

    send_replies(conversation, Array(result[:mensagens]), trigger_message_id, agent_key, encerrou: self.class.farewell?(result))
    # 🩺 item 251 + auditoria 10/2026 (#458): chamar humano SEMPRE deixa uma
    # tarefa com responsável no Meu Painel (e aviso no Radar quando é urgência
    # clínica) — nos três atendentes (antes só no pós-operatório)
    hand_over!(conversation, result, agent_key) if result[:chamar_humano]
    detail = "etapa #{result[:etapa]} · #{Array(result[:mensagens]).size} msg(s)"
    detail += " · 🔧 #{acoes_text(result)}" if Array(result[:acoes]).any?
    log_event(account, agent_key, conversation, booked ? 'agendou' : 'respondeu', detail.truncate(220))
  end

  # ── 🚫 cancelar=true sem ferramenta (#457) ──────────────────────────────
  CANCEL_PENDING_TEXT = 'Anotei o seu pedido de cancelamento e passei para a equipe da clínica, que confirma com você por aqui ' \
                        'no próximo horário de atendimento.'.freeze
  # a tarefa para a equipe não nasceu (erro do sistema): sem promessa de "passei para a equipe"
  CANCEL_FAILED_TEXT = 'Não consegui registrar o cancelamento agora. A clínica confirma o cancelamento com você por aqui ' \
                       'no próximo horário de atendimento.'.freeze
  CANCEL_EVENT_NOTES = { tarefa: 'pediu cancelar sem consulta própria na Agenda — tarefa aberta para a equipe',
                         sem_tarefa: 'pediu cancelar e a tarefa para a equipe NÃO foi aberta — conferir a conversa' }.freeze
  # o pedido é sobre a consulta de OUTRA pessoa (mãe, filho, esposa...)? aí o
  # atalho não serve: nunca cancelar a consulta do próprio contato no lugar da certa
  SOMEONE_ELSE_RE = /\b(m[ãa]e|pai|filh\w*|espos\w*|marid\w*|irm[ãa]\w*|outra pessoa|dela|dele)\b/i

  # a IA já resolveu o cancelamento nesta resposta? = chamou cancelar_consulta
  # e deu ok, OU a ferramenta recusou por ser consulta de OUTRA pessoa (ela já
  # abriu a tarefa e orientou a IA). Recusa por "não encontrada" / "não
  # confirmou" NÃO conta: aí o job cancela a consulta do contexto ou fala a verdade.
  def cancel_handled?(result)
    Array(result[:acoes]).any? { |a| a['ferramenta'] == 'cancelar_consulta' && (a['ok'] || a['resumo'].to_s.include?('outra pessoa')) }
  end

  def about_someone_else?(result)
    [*Array(result[:mensagens]), result[:leitura]].join(' ').match?(SOMEONE_ELSE_RE)
  end

  # cancela pela MESMA ferramenta que a IA usaria (Crm::ResponderTools, ao
  # vivo), só a consulta futura do PRÓPRIO contato (a regra de dono da
  # ferramenta vale igual) e só quando a conversa é sobre a consulta DELE.
  # Devolve :cancelada, :tarefa (não cancelou; tarefa aberta para a equipe) ou
  # :sem_tarefa (nem a tarefa nasceu — o chamador não promete nada ao paciente).
  def cancel_own_appointment!(conversation, result, agent_key)
    contact = conversation.contact
    return :cancelada if !about_someone_else?(result) && cancel_by_tool!(conversation, result, agent_key, contact)

    motivo = if about_someone_else?(result)
               'Paciente pediu para cancelar uma consulta que parece ser de OUTRA pessoa (nada foi cancelado)'
             else
               'Paciente pediu para cancelar a consulta e o sistema não achou a consulta dele para cancelar'
             end
    Crm::HandoffTask.open!(account: conversation.account, contact: contact, conversation: conversation, agent_key: agent_key,
                           motivo: motivo, urgencia: 'normal',
                           detalhes: "O que o agente entendeu: #{result[:leitura]}\nConferir na Agenda e confirmar com o paciente.")
    :tarefa
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgentJob] tarefa do cancelamento: #{e.message}"
    :sem_tarefa
  end

  # devolve true só se a ferramenta cancelou de verdade (ok e não simulado)
  def cancel_by_tool!(conversation, result, agent_key, contact)
    task = Crm::AppointmentRecorder.future_appointment(conversation.account, contact&.phone_number, nil, contact)
    return false unless task

    tools = Crm::ResponderTools.new(conversation: conversation, agent_key: agent_key, live: true)
    outcome = tools.call('cancelar_consulta', 'id' => task.id, 'motivo' => result[:leitura].to_s.first(120))
    result[:acoes] = Array(result[:acoes]) + tools.acoes
    outcome.is_a?(Hash) && outcome[:ok] == true && !outcome[:simulado]
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgentJob] cancelar pela ferramenta: #{e.message}"
    false
  end

  # ── 🚨 urgência clínica (#443) ───────────────────────────────────────────
  # só os SINAIS do Roteiro — a palavra "urgência" sozinha não entra ("sem
  # urgência", "insiste com urgência" marcavam a conversa como urgente)
  URGENCY_RE = /pronto[ -]atendimento|dor (forte|intensa)|perda (s[úu]bita )?d[ae] vis[ãa]o|trauma/i
  ORIENTATION_GAP = 1.hour
  URGENT_WAIT_TEXT = 'Se estiver piorando, não espere por aqui: procure um pronto atendimento oftalmológico agora. ' \
                     'Sua mensagem fica registrada e a clínica responde no próximo horário de atendimento.'.freeze

  # a passagem para humano foi por urgência clínica? (tarefa alta aberta pela
  # IA, ou os balões/leitura falam de pronto atendimento, dor forte, perda de visão)
  def clinical_urgency?(result)
    return true if Array(result[:acoes]).any? { |a| a['ferramenta'] == 'abrir_tarefa' && a['ok'] && a['resumo'].to_s.include?('(alta)') }

    [*Array(result[:mensagens]), result[:leitura]].join(' ').match?(URGENCY_RE)
  end

  # pausado por urgência: orientação fixa (sem IA), no máximo uma a cada hora,
  # e só enquanto ninguém da equipe respondeu. O CrmListener tira a marca
  # 'urgente' quando uma pessoa responde; esta conferência é a segunda camada
  # (resposta humana depois da pausa = a equipe assumiu = silêncio).
  def urgent_orientation!(account, conversation, trigger_message_id, agent_key, state)
    last = Time.zone.parse(state['orientacao_at'].to_s)
    return if last && last > ORIENTATION_GAP.ago
    return if human_replied_since?(conversation, state['at'])

    send_replies(conversation, [URGENT_WAIT_TEXT], trigger_message_id, agent_key)
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      attrs.merge(STATE_KEY => (attrs[STATE_KEY] || state).merge('orientacao_at' => Time.current.iso8601))
    end
    log_event(account, agent_key, conversation, 'orientacao_urgencia', 'pausado por urgência: repetiu a orientação de pronto atendimento')
  end

  # alguém de verdade (pessoa da equipe, não robô) respondeu depois da pausa?
  def human_replied_since?(conversation, since)
    from = Time.zone.parse(since.to_s) || 1.day.ago
    conversation.messages.where(message_type: :outgoing, sender_type: 'User').where('created_at > ?', from)
                .where("COALESCE(additional_attributes ->> 'cevico_ia_agent', '') = ''").exists?
  end

  # 🚨 (#443) agente configurado AO VIVO, mas fora da janela (madrugada, fim de
  # semana): a resposta fica em sombra (o N8N pode estar atendendo), mas uma
  # URGÊNCIA clínica não fica só na nota — abre a tarefa de verdade (🔴 + aviso
  # no Radar), para a equipe ver assim que abrir o painel
  OUTSIDE_WINDOW_NOTE = 'urgência clínica fora da janela ao vivo: tarefa 🔴 aberta; o paciente NÃO recebeu resposta do agente'.freeze

  def urgent_outside_window!(account, conversation, cfg, agent_key, result)
    return unless live_but_outside_window?(cfg) && result[:chamar_humano] && clinical_urgency?(result)

    detalhes = "Fora da janela ao vivo: o agente NÃO respondeu ao paciente. O que teria dito: #{Array(result[:mensagens]).join(' ')}"
    Crm::HandoffTask.open!(account: account, contact: conversation.contact, conversation: conversation, agent_key: agent_key,
                           motivo: result[:leitura].to_s.presence || 'Urgência relatada fora do horário do agente',
                           detalhes: detalhes, urgencia: 'alta')
    log_event(account, agent_key, conversation, 'urgencia_fora_da_janela', OUTSIDE_WINDOW_NOTE)
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgentJob] urgência fora da janela: #{e.message}"
  end

  # agente marcado "ao vivo" na tela, mas AGORA fora da janela (dia/hora)
  def live_but_outside_window?(cfg)
    LIVE_ENABLED && cfg['mode'] == 'live' && !self.class.within_window?(cfg)
  end

  # 🛟 item 291 (29/09, "algumas conversas tiveram continuidade, outras não"): a
  # chamada da IA pode falhar por um instante (serviço cheio, limite por
  # minuto, rede). Antes o erro era anotado e o paciente ficava SEM resposta.
  # Agora tenta de novo em 20 s, 1 min e 3 min — sempre conferindo se aquela
  # ainda é a última mensagem do paciente (o perform já faz isso). Erro de
  # configuração (agente desligado, sem chave) não adianta repetir.
  RETRY_WAITS = [20.seconds, 1.minute, 3.minutes].freeze
  PERMANENT_ERRORS = /Agente desligado|Configure a chave|Conversa vazia/
  RETRY_KEY = 'cevico:responder:retry:%<id>s'.freeze

  def retry_later(conversation, trigger_message_id, agent_key, error)
    return nil if error.to_s.match?(PERMANENT_ERRORS)

    key = format(RETRY_KEY, id: trigger_message_id)
    attempt = Redis::Alfred.incr(key).to_i
    Redis::Alfred.expire(key, 6.hours.to_i)
    wait = RETRY_WAITS[attempt - 1]
    return nil unless wait

    self.class.set(wait: wait).perform_later(conversation.id, trigger_message_id, agent_key)
    attempt
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgentJob] nova tentativa não agendada: #{e.message}"
    nil
  end

  SLOT_TAKEN_TEXT = 'Poxa, esse horário acabou de ser preenchido. Me diz outro período que você prefere, que eu vejo o mais próximo pra você?'.freeze
  # a IA mandou agendar sem dia/hora: pede o que falta (dizer que "o horário
  # foi preenchido" seria mentira — ninguém pegou vaga nenhuma)
  MISSING_SLOT_TEXT = 'Só me confirma o dia e a hora que você prefere? Assim já deixo reservado pra você.'.freeze

  # item 200 ("rodando solto"): agendar e encerrar NÃO pausam mais — o
  # paciente que volta dias depois ("quero remarcar") é atendido na hora.
  # Só a passagem para humano pausa (hand_over!; a equipe manda 👍 para reativar).

  # trava por conta+dia+hora+unidade → confere de novo → grava na Agenda
  def book!(account, conversation, result, agent_key, cfg = {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    ag = (result[:agendamento] || {}).symbolize_keys
    date = begin
      Date.parse(ag[:dia].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    time = ag[:hora].to_s.strip
    return :sem_horario if date.nil? || time.blank?

    lock_manager = Redis::LockManager.new
    lock_key = "CRM_SLOT_LOCK::#{account.id}::#{date}::#{time}::#{ag[:unidade]}"
    return false unless lock_manager.lock(lock_key, 30.seconds)

    begin
      return false unless Crm::AgendaSlots.slot_available?(account, date: date, time: time, unit: ag[:unidade])

      starts_at = Crm::AgendaSlots::TZ.parse("#{date} #{time}")
      doctor = Crm::AgendaSlots.doctor_at(account, date, time, ag[:unidade]) # item 311: o médico da faixa do horário
      outcome = Crm::AppointmentRecorder.record(
        account: account,
        result: { found: true, starts_at: starts_at, name: ag[:nome], phone: ag[:telefone].presence || conversation.contact&.phone_number,
                  # 💰 (#132) sem preço fixo: o valor da consulta vem do pré-configurado (item 324)
                  unit: ag[:unidade], procedure: ag[:procedimento], doctor: doctor,
                  notes: "Agendado pelo #{agent_name(agent_key)} (WhatsApp)" },
        contact: conversation.contact, conversation: conversation
      )
      # a Agenda não gravou (:skipped — conta sem criador, por exemplo): sem
      # consulta na Agenda não existe "Deu certo"
      unless %i[created rescheduled already].include?(outcome)
        log_event(account, agent_key, conversation, 'erro', "#{ag[:dia]} #{ag[:hora]} não entrou na Agenda (#{outcome})")
        return false
      end

      # item 200: etiqueta + card na coluna (a do card do agente ou a da tela Agendamentos)
      effects = Crm::BookingSideEffects.apply(account: account, contact: conversation.contact, conversation: conversation,
                                              outcome: outcome == :rescheduled ? :rescheduled : :created,
                                              stage_id: cfg['after_booking_stage_id'].presence ||
                                                        agent_cfg(account, 'atendente_agendamento')['after_booking_stage_id'])
      effects_text = Crm::BookingSideEffects.summary(effects)
      conversation.messages.create!(
        account_id: account.id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
        content: "📅 #{agent_name(agent_key)} agendou: #{ag[:nome]} — #{starts_at.strftime('%d/%m/%Y às %H:%M')} " \
                 "(#{Crm::AgendaSlots::UNIT_LABELS[ag[:unidade]] || ag[:unidade]}). " \
                 "[📆 Ver na agenda](/app/accounts/#{account.id}/agenda?date=#{starts_at.strftime('%Y-%m-%d')})" \
                 "#{" #{effects_text}" if effects_text.present?}"
      )
      true
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  # item 200: balões curtos e ESPAÇADOS — 3 s entre um e outro (como quem digita)
  BALLOON_GAP = 3

  # 🧠 follow-up inteligente (13/10): resposta de DESPEDIDA (etapa encerramento
  # ou "minha função terminou", sem passar para a equipe) — o robô de follow-up
  # não cutuca depois dela. Caso real: Adriano, "Oi, pode falar?" 25 min após o tchau.
  def self.farewell?(result)
    (result[:etapa].to_s == 'encerramento' || result[:pausar] == true) && result[:chamar_humano] != true
  end

  def send_replies(conversation, texts, trigger_message_id, agent_key, encerrou: false)
    # 🔁 (#100) última conferência antes de falar: alguém já respondeu esta mensagem?
    return if self.class.already_replied?(conversation, trigger_message_id)

    attrs = { 'cevico_ia_agent' => agent_key }
    attrs['cevico_encerrou'] = true if encerrou # carimbo lido pelo Crm::FollowupClosure
    texts.first(3).each_with_index do |text, index|
      clean = text.to_s.tr('—', ',').gsub(/\s?😊/, '').strip # sem travessão nem a carinha que pausa (o sistema garante)
      next if clean.blank?

      sleep BALLOON_GAP if index.positive?
      break if last_incoming_id(conversation) != trigger_message_id

      conversation.messages.create!(
        account_id: conversation.account_id, inbox_id: conversation.inbox_id,
        message_type: :outgoing, content: clean,
        additional_attributes: attrs
      )
    end
  end

  # passagem para a equipe, sempre na mesma ordem: tarefa → nota (dizendo se a
  # tarefa nasceu) → pausa (com a marca de urgência clínica, se for o caso)
  def hand_over!(conversation, result, agent_key, task_opened: false)
    task_opened = ensure_handoff_task(conversation, result, agent_key) || task_opened if result[:chamar_humano]
    handoff_note(conversation, agent_key, task_opened: task_opened)
    pause!(conversation, 'chamou_humano', agent_key, urgente: clinical_urgency?(result))
  end

  # devolve true se a tarefa existe (aberta agora, complementada, ou aberta
  # pela própria IA com abrir_tarefa). Urgência 'alta' (🔴 + aviso no Radar)
  # só para urgência clínica; o resto vira tarefa normal com dono no Meu
  # Painel — senão o Radar enche de vermelho e a urgência de verdade some.
  def ensure_handoff_task(conversation, result, agent_key)
    return true if Array(result[:acoes]).any? { |a| a['ferramenta'] == 'abrir_tarefa' && a['ok'] }

    Crm::HandoffTask.open!(account: conversation.account, contact: conversation.contact, conversation: conversation,
                           agent_key: agent_key, motivo: result[:leitura].to_s.presence || 'Paciente pediu atenção da equipe',
                           detalhes: Array(result[:mensagens]).join(' '), urgencia: clinical_urgency?(result) ? 'alta' : 'normal')
    true
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderAgentJob] tarefa de passagem: #{e.message}"
    false
  end

  def handoff_note(conversation, agent_key, task_opened: true)
    task_text = task_opened ? 'tarefa aberta no Meu Painel' : 'NÃO consegui abrir a tarefa — confira o Meu Painel'
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :activity, private: true,
      content: "🙋 #{agent_name(agent_key)} pediu ATENDIMENTO HUMANO nesta conversa (#{task_text}). " \
               'Responda por aqui — o agente fica pausado; ligue de novo pelo botão do painel (ou mande 👍).'
    )
  end

  # urgente: true (#443) = pausa por urgência clínica — o CrmListener ainda
  # manda a mensagem seguinte do paciente para cá, e o job repete a orientação
  def pause!(conversation, reason, agent_key, urgente: false)
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      value = { 'paused' => true, 'reason' => reason, 'agent' => agent_key, 'at' => Time.current.iso8601 }
      value['urgente'] = true if urgente
      attrs.merge(STATE_KEY => value)
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
    Crm::ResponderTools::AGENT_NAMES[agent_key] || agent_key
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
