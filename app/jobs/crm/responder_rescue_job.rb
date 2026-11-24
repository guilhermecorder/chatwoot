# 🛟 RESGATE do Atendente de IA (item 291, 29/09): "algumas conversas tiveram
# continuidade, outras não". A cada 5 min procura conversas ABERTAS, nas caixas
# atendidas por um agente AO VIVO, em que a ÚLTIMA mensagem é do paciente e
# ficou sem resposta — e devolve a conversa para o agente dono da coluna.
# Cobre o que a nova tentativa do job não cobre: job que morreu no meio
# (deploy, fila reiniciada), erro fora da chamada da IA, motor fora do ar.
# Seguro por construção: só reenfileira o MESMO job (que confere pausa, janela,
# teto diário, se a mensagem ainda é a última e se já foi respondida). E
# respeita a cerca dos parceiros (auditoria 10/2026): paciente do Oftalmofácil
# nunca volta à IA.
#
# 🛟 23/11 (RESGATE QUE NÃO DESISTE): em 23/11 a chave da IA bateu no limite;
# depois de 2 h o resgate desistia e cada mensagem só tinha UMA chance. Agora:
# - janela de 3 min até 23 h (ai_config responder_rescue_max_hours; fica dentro
#   das 24 h em que o WhatsApp deixa responder);
# - a MESMA mensagem volta a ser resgatada enquanto a tentativa anterior
#   terminou em erro do motor (ou o job morreu no meio): desfecho gravado pelo
#   Crm::ResponderAgentJob. Tentativa que terminou bem e não gerou resposta
#   (pausa, teto, IA sem nada a dizer) continua valendo uma vez só;
# - no máximo uma tentativa por mensagem a cada 30 min (marca SET NX no Redis)
#   e nunca se já existe resposta (só entra quem tem a última fala do paciente);
# - no máximo 15 conversas por rodada e por conta (responder_rescue_per_round),
#   da mais recente para a mais antiga: quando o motor volta, a fila escoa em
#   rodadas de 5 min em vez de disparar tudo de uma vez;
# - pausa com prazo vencido não segura mais o resgate (Crm::ResponderPause).
class Crm::ResponderRescueJob < ApplicationJob
  queue_as :low

  WAITED_MIN = 3.minutes
  RETRY_GAP = 30.minutes
  # depois deste tempo de espera só entra quem ficou sem resposta por erro do motor
  OUTAGE_ONLY_AFTER = 2.hours
  # quantas conversas da janela são olhadas por rodada (uma consulta leve por
  # conversa) e quantas candidatas a lista devolve
  SCAN_LIMIT = 500
  LIMIT = 120
  RESCUE_KEY = 'cevico:responder:rescue:%<id>s'.freeze
  # "esta mensagem já foi resgatada alguma vez" (24 h): a partir da 2ª vez só
  # volta quem teve erro do motor
  RESCUED_KEY = 'cevico:responder:rescue:feito:%<id>s'.freeze
  CERCA_KEY = 'cevico:responder:rescue:cerca:%<id>s'.freeze
  KEYS = %w[atendente_agendamento atendente_pos atendente_pos_op].freeze

  def perform
    # 🚨 #217: com os robôs desligados a rodada também conta (o cron está vivo)
    return Crm::CronHealth.ran!('resgate') unless Crm::ResponderAgentJob::LIVE_ENABLED

    CrmSetting.where("ai_config -> 'agents' IS NOT NULL").find_each do |settings|
      rescue_account(settings)
    rescue StandardError => e
      Rails.logger.error "[Crm::ResponderRescueJob] conta #{settings.account_id}: #{e.message}"
      Crm::CronHealth.failed!('resgate', e, account: settings.account) # 🚨 #217: avisa se repetir
    end
    Crm::CronHealth.ran!('resgate') # 🚨 #217: sinal de vida da rodada (o vigia confere)
  end

  # até quando o resgate insiste (ai_config responder_rescue_max_hours; padrão 23 h)
  def self.max_wait(cfg)
    Crm::ResponderPause.setting(cfg, 'responder_rescue_max_hours').hours
  end

  # conversas que o resgate devolveria agora, da mais recente para a mais
  # antiga (também usado pela tela/console). cfg = ai_config da conta.
  def self.waiting(account, agents, now: Time.current, cfg: nil) # rubocop:disable Metrics/CyclomaticComplexity
    inbox_ids = agents.values.flat_map { |a| Array(a['inbox_ids']).map(&:to_i) }.uniq
    return [] if inbox_ids.empty?

    cfg ||= CrmSetting.find_by(account: account)&.ai_config || {}
    oldest = now - max_wait(cfg)
    account.conversations.open.where(inbox_id: inbox_ids)
           .where(last_activity_at: oldest..(now - WAITED_MIN))
           .order(last_activity_at: :desc).limit(SCAN_LIMIT)
           .filter_map { |conversation| candidate(conversation, now, oldest: oldest, cfg: cfg) }.first(LIMIT)
  end

  # [conversa, mensagem] quando a última fala é do paciente e ninguém respondeu
  def self.candidate(conversation, now, oldest: now - max_wait(nil), cfg: nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    last = conversation.messages.where(private: false, message_type: %i[incoming outgoing]).order(:id).last
    return nil unless last&.incoming?
    return nil if last.created_at > now - WAITED_MIN || last.created_at < oldest
    # 🛟 23/11: a janela longa (de 2 h até 23 h) é SÓ para pane do motor —
    # mensagem cuja tentativa terminou em erro ou morreu no meio. Mensagem
    # antiga que nunca foi tentada (pausa que venceu, conversa que ficou com a
    # última palavra do paciente) não ganha resposta horas depois.
    return nil if last.created_at < now - OUTAGE_ONLY_AFTER && !outage_victim?(last)
    # 🔁 23/11: só a pausa que AINDA vale segura (a de prazo vencido não conta;
    # quem limpa e deixa a nota é o próprio job do agente ao responder)
    return nil if Crm::ResponderPause.active?(conversation, cfg)
    return nil if partner_blocked?(conversation, last)

    [conversation, last]
  end

  # a tentativa de responder esta mensagem terminou em erro do motor (ou o job morreu no meio)?
  def self.outage_victim?(message)
    Crm::ResponderAgentJob::RETRIABLE_OUTCOMES.include?(Crm::ResponderAgentJob.outcome(message.id))
  end

  # 🚧 cerca dos parceiros (auditoria #63/#98/#253/#459): o CrmListener deixou
  # a mensagem do paciente de parceiro SEM resposta de propósito — o resgate
  # não pode "devolver" essa conversa à IA. Fica UMA linha no log por mensagem
  # (a tela e o cron de 5 min passam aqui várias vezes pela mesma conversa).
  def self.partner_blocked?(conversation, message)
    return false unless Crm::PartnerGuard.partner_conversation?(conversation)

    # (24 h: a janela do resgate agora vai até 23 h e a linha no log continua sendo uma só)
    Crm::PartnerGuard.block!('resgate do atendente', conversation: conversation) if first_time?(format(CERCA_KEY, id: message.id), 24.hours)
    true
  end

  # marca SET NX: só a primeira passagem por esta chave (até ela expirar) devolve true
  def self.first_time?(key, ttl = 6.hours)
    Redis::Alfred.set(key, Time.current.to_i, nx: true, ex: ttl.to_i) ? true : false
  end

  private

  def rescue_account(settings) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
    agents = live_agents(settings)
    return if agents.empty?

    cfg = settings.ai_config
    left = Crm::ResponderPause.setting(cfg, 'responder_rescue_per_round')
    self.class.waiting(settings.account, agents, cfg: cfg).each do |conversation, message|
      break unless left.positive? # 🛟 23/11: o resto fica para a próxima rodada (5 min)

      mine = agents.select { |_key, a| Array(a['inbox_ids']).map(&:to_i).include?(conversation.inbox_id) }
      key = CrmListener.instance.send(:responder_owner_for, conversation, mine)
      next if key.blank?
      # (#100) conversa travada por outro job (o original ainda rodando, ou morto
      # com a trava no Redis até ela expirar)? não gasta a vez do resgate agora
      # — a conversa continua candidata e a próxima rodada (5 min) resgata
      next if Redis::LockManager.new.locked?(format(Crm::ResponderAgentJob::LOCK_KEY, id: conversation.id))
      next unless rescue_turn?(message)

      Crm::ResponderAgentJob.perform_later(conversation.id, message.id, key)
      left -= 1
      log(settings, key, conversation, message)
    end
  end

  def live_agents(settings)
    ((settings.ai_config || {})['agents'] || {}).slice(*KEYS).select do |_key, a|
      a['enabled'] == true && Crm::ResponderAgentJob.live_mode?(a)
    end
  end

  # 🛟 23/11: é a vez desta mensagem? A 1ª vez sempre passa. Da 2ª em diante só
  # volta quem teve a tentativa anterior terminada em erro do motor (ou
  # interrompida no meio): desfecho 'erro'/'pendente' do Crm::ResponderAgentJob.
  # E no máximo uma tentativa a cada 30 min (SET NX que expira sozinho).
  def rescue_turn?(message)
    rescued_key = format(RESCUED_KEY, id: message.id)
    if Redis::Alfred.get(rescued_key).present? &&
       Crm::ResponderAgentJob::RETRIABLE_OUTCOMES.exclude?(Crm::ResponderAgentJob.outcome(message.id))
      return false
    end
    return false unless self.class.first_time?(format(RESCUE_KEY, id: message.id), RETRY_GAP)

    Redis::Alfred.set(rescued_key, Time.current.to_i, ex: Crm::ResponderAgentJob::OUTCOME_TTL.to_i)
    true
  end

  def log(settings, key, conversation, message) # rubocop:disable Metrics/AbcSize
    waited = ((Time.current - message.created_at) / 60).round
    settings.with_lock do
      cfg = settings.ai_config || {}
      state = cfg["#{key}_state"] || {}
      event = { 'at' => Time.current.iso8601, 'type' => 'resgate', 'conversation_id' => conversation.display_id,
                'contact' => conversation.contact&.name.to_s.truncate(40),
                'note' => "paciente esperava há #{waited} min sem resposta — devolvi ao agente" }
      state['events'] = [event] + Array(state['events']).first(Crm::ResponderAgentJob::LOG_CAP - 1)
      cfg["#{key}_state"] = state
      settings.update!(ai_config: cfg)
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderRescueJob] registro: #{e.message}"
  end
end
