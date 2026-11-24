# ⏱️ A IA VOLTA SOZINHA (13/11/2026, Guilherme): "eu quero que essa chavinha religue. Eu nunca quero deixar o
# cliente sem atendimento… alguns minutos depois do atendimento humano, mesmo que o humano esqueça de religar a
# chavinha, ele tem um timerzinho… 2, 3 minutos depois do atendimento humano, sem resposta, sem nada, ele já religa."
#
# A cada minuto, nas contas com ai_config.auto_resume.enabled: conversa ABERTA com o Atendente IA pausado
# (alguém da equipe respondeu, o agente chamou um humano ou a chavinha foi desligada) e SEM mensagem da equipe há
# N minutos (padrão 3) → religa a IA, deixa nota interna e, se o cliente escreveu depois disso e ninguém respondeu,
# devolve a mensagem ao agente dono da coluna na hora (o mesmo job de sempre, que confere janela, teto e cerca).
#
# NÃO religa: pausa por URGÊNCIA clínica (#443) nem por teto diário de mensagens (proteção). A conta de tempo
# parte da ÚLTIMA mensagem humana (ou da pausa, o que for mais recente): enquanto a pessoa da equipe conversa,
# cada mensagem dela empurra o relógio.
#
# ⏱️ 24/11 (LIFE, pedido do Fernando pelo Guilherme): "quando ele estiver conversando com as pessoas, ela não vai
# conflitar com o que ele está falando… quando ele desativar, ficar pelo menos 10 minutos desligada… a partir de
# orçamento enviado". auto_resume.minutes_pos = minutos a partir da coluna "Orçamento Enviado" (e todas as que vêm
# depois: vistoria, negociação, contrato…); antes dela continua auto_resume.minutes (3), para o orçamento não esperar.
class Crm::ResponderAutoResumeJob < ApplicationJob
  queue_as :high

  DEFAULT_MINUTES = 3
  MINUTES_RANGE = (1..120)
  REASONS = %w[humano_assumiu chamar_humano chamou_humano botao].freeze
  ANSWER_MAX_AGE = 2.hours # mensagem do cliente mais velha que isso não é respondida na volta (o resgate também não)
  LIMIT = 100

  def self.config(settings)
    raw = (settings&.ai_config || {})['auto_resume']
    return nil unless raw.is_a?(Hash) && raw['enabled'] == true

    minutes = raw['minutes'].to_i
    minutes = DEFAULT_MINUTES unless MINUTES_RANGE.cover?(minutes)
    pos = raw['minutes_pos'].to_i
    { 'enabled' => true, 'minutes' => minutes, 'minutes_pos' => MINUTES_RANGE.cover?(pos) ? pos : nil }.compact
  end

  # os minutos desta conversa: depois do orçamento enviado, os de 'minutes_pos' (quando configurados)
  def self.minutes_for(conversation, cfg)
    return cfg['minutes'] if cfg['minutes_pos'].nil? || !after_quote_sent?(conversation)

    cfg['minutes_pos']
  end

  QUOTE_SENT_STAGE = /or[çc]amento enviado/i

  # o card está na coluna "Orçamento Enviado" ou numa coluna depois dela, no mesmo funil
  def self.after_quote_sent?(conversation)
    contact_id = conversation.contact_id
    stage = contact_id && Crm::Contact.where(contact_id: contact_id).order(:updated_at).last&.stage
    return false if stage.nil?

    mark = Crm::Stage.where(pipeline_id: stage.pipeline_id).order(:position).detect { |s| s.name.to_s.match?(QUOTE_SENT_STAGE) }
    mark.present? && stage.position.to_i >= mark.position.to_i
  end

  # pausa que o relógio religa?
  def self.eligible?(state)
    state.is_a?(Hash) && state['paused'] == true && state['urgente'] != true && REASONS.include?(state['reason'].to_s)
  end

  # quando a IA volta nesta conversa (nil = não volta sozinha)
  def self.resume_at(conversation, state, minutes)
    return nil unless eligible?(state)

    reference(conversation, state) + minutes.minutes
  end

  # a pausa ou a última mensagem de uma pessoa da equipe, o que for mais recente
  def self.reference(conversation, state)
    paused_at = Time.zone.parse(state['at'].to_s) rescue nil # rubocop:disable Style/RescueModifier
    human_at = last_human_at(conversation)
    [paused_at, human_at].compact.max || conversation.updated_at
  end

  def self.last_human_at(conversation)
    conversation.messages.where(message_type: :outgoing, private: false, sender_type: 'User')
                .order(id: :desc).limit(20)
                .detect { |m| CrmListener.instance.send(:human_outgoing?, m) }&.created_at
  end

  def perform(now = Time.current)
    CrmSetting.where("ai_config -> 'auto_resume' ->> 'enabled' = 'true'").find_each do |settings|
      resume_account(settings, now)
    rescue StandardError => e
      Rails.logger.error "[Crm::ResponderAutoResumeJob] conta #{settings.account_id}: #{e.message}"
    end
  end

  private

  def resume_account(settings, now)
    cfg = self.class.config(settings)
    agents = live_agents(settings)
    return if cfg.nil? || agents.empty?

    inbox_ids = agents.values.flat_map { |a| Array(a['inbox_ids']).map(&:to_i) }.uniq
    settings.account.conversations.open.where(inbox_id: inbox_ids)
            .where("conversations.additional_attributes -> ? ->> 'paused' = 'true'", Crm::ResponderAgentJob::STATE_KEY)
            .order(last_activity_at: :desc).limit(LIMIT).each do |conversation|
      resume_one(conversation, agents, self.class.minutes_for(conversation, cfg), now)
    end
  end

  def resume_one(conversation, agents, minutes, now)
    state = (conversation.additional_attributes || {})[Crm::ResponderAgentJob::STATE_KEY] || {}
    at = self.class.resume_at(conversation, state, minutes)
    return if at.nil? || at > now

    ref = self.class.reference(conversation, state)
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge(Crm::ResponderAgentJob::STATE_KEY => {}) }
    conversation.messages.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
                                  private: true,
                                  content: "▶️ Atendente IA religado sozinho: #{minutes} min sem mensagem da equipe nesta conversa.")
    answer_waiting(conversation, agents, ref, now)
  end

  # o cliente escreveu depois da última fala da equipe e ninguém respondeu → o agente responde já
  def answer_waiting(conversation, agents, ref, now) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    last = conversation.messages.where(private: false, message_type: %i[incoming outgoing]).order(:id).last
    return unless last&.incoming? && last.created_at > ref && last.created_at > now - ANSWER_MAX_AGE
    return if Crm::ResponderRescueJob.partner_blocked?(conversation, last)

    mine = agents.select { |_key, a| Array(a['inbox_ids']).map(&:to_i).include?(conversation.inbox_id) }
    key = CrmListener.instance.send(:responder_owner_for, conversation, mine)
    return if key.blank?
    # a mesma marca do resgate: a mensagem é devolvida ao agente uma vez só
    return unless Crm::ResponderRescueJob.first_time?(format(Crm::ResponderRescueJob::RESCUE_KEY, id: last.id))

    Crm::ResponderAgentJob.perform_later(conversation.id, last.id, key)
  end

  def live_agents(settings)
    ((settings.ai_config || {})['agents'] || {}).slice(*CrmListener::RESPONDER_KEYS).select do |_key, a|
      a['enabled'] == true && Crm::ResponderAgentJob.live_mode?(a)
    end
  end
end
