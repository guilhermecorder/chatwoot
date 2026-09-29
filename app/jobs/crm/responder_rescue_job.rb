# 🛟 RESGATE do Atendente de IA (item 291, 29/09): "algumas conversas tiveram
# continuidade, outras não". A cada 5 min procura conversas ABERTAS, nas caixas
# atendidas por um agente AO VIVO, em que a ÚLTIMA mensagem é do paciente e
# ficou sem resposta entre 3 minutos e 2 horas — e devolve a conversa para o
# agente dono da coluna. Cobre o que a nova tentativa do job não cobre: job que
# morreu no meio (deploy, fila reiniciada), erro fora da chamada da IA.
# Seguro por construção: só reenfileira o MESMO job (que confere pausa, janela,
# teto diário e se a mensagem ainda é a última) e cada mensagem é resgatada
# UMA vez só (marca no Redis) — nunca vira rajada.
class Crm::ResponderRescueJob < ApplicationJob
  queue_as :low

  WAITED_MIN = 3.minutes
  WAITED_MAX = 2.hours
  LIMIT = 40
  RESCUE_KEY = 'cevico:responder:rescue:%<id>s'.freeze
  KEYS = %w[atendente_agendamento atendente_pos atendente_pos_op].freeze

  def perform
    return unless Crm::ResponderAgentJob::LIVE_ENABLED

    CrmSetting.where("ai_config -> 'agents' IS NOT NULL").find_each do |settings|
      rescue_account(settings)
    rescue StandardError => e
      Rails.logger.error "[Crm::ResponderRescueJob] conta #{settings.account_id}: #{e.message}"
    end
  end

  # conversas que o resgate devolveria agora (também usado pela tela/console)
  def self.waiting(account, agents, now: Time.current)
    inbox_ids = agents.values.flat_map { |a| Array(a['inbox_ids']).map(&:to_i) }.uniq
    return [] if inbox_ids.empty?

    account.conversations.open.where(inbox_id: inbox_ids)
           .where(last_activity_at: (now - WAITED_MAX)..(now - WAITED_MIN))
           .order(:last_activity_at).limit(LIMIT * 3)
           .filter_map { |conversation| candidate(conversation, now) }.first(LIMIT)
  end

  # [conversa, mensagem] quando a última fala é do paciente e ninguém respondeu
  def self.candidate(conversation, now)
    last = conversation.messages.where(private: false, message_type: %i[incoming outgoing]).order(:id).last
    return nil unless last&.incoming?
    return nil if last.created_at > now - WAITED_MIN || last.created_at < now - WAITED_MAX
    return nil if (conversation.additional_attributes || {}).dig(Crm::ResponderAgentJob::STATE_KEY, 'paused')

    [conversation, last]
  end

  private

  def rescue_account(settings)
    agents = live_agents(settings)
    return if agents.empty?

    self.class.waiting(settings.account, agents).each do |conversation, message|
      mine = agents.select { |_key, a| Array(a['inbox_ids']).map(&:to_i).include?(conversation.inbox_id) }
      key = CrmListener.instance.send(:responder_owner_for, conversation, mine)
      next if key.blank?
      next unless first_rescue?(message)

      Crm::ResponderAgentJob.perform_later(conversation.id, message.id, key)
      log(settings, key, conversation, message)
    end
  end

  def live_agents(settings)
    ((settings.ai_config || {})['agents'] || {}).slice(*KEYS).select do |_key, a|
      a['enabled'] == true && Crm::ResponderAgentJob.live_mode?(a)
    end
  end

  # só a primeira vez passa (SET NX): a mesma mensagem nunca é resgatada de novo
  def first_rescue?(message)
    Redis::Alfred.set(format(RESCUE_KEY, id: message.id), Time.current.to_i, nx: true, ex: 6.hours.to_i) ? true : false
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
