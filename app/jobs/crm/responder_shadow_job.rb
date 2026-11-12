# 🕶️ SOMBRA AO LADO (LIFE, 12/11/2026 · Atendente do Orçamento): um atendente pode
# OBSERVAR colunas que são de outro atendente (campo `sombra_stage_ids`). A mensagem
# do cliente continua indo ao DONO da coluna (CrmListener#responder_owner_for), que
# responde como sempre, e vai TAMBÉM a este observador, que só escreve a nota de
# sombra ("teria respondido"). Serve para comparar um atendente novo com o que está
# no ar ANTES de trocar o dono da coluna — na tela Sombra os dois ficam lado a lado.
#
# Diferenças para o Crm::ResponderAgentJob (de quem herda a sombra inteira):
# - NUNCA fala com o cliente, mesmo com o modo "ao vivo" marcado: para falar, a
#   coluna tem que ser dele (stage_ids) — e aí quem roda é o job normal;
# - não pega a trava da conversa: o dono está respondendo de verdade e não pode
#   esperar a IA do observador;
# - a nota é POR AGENTE: dono em sombra e observador na mesma mensagem = 2 notas;
# - a nota leva o nome que a conta deu ao agente (campo `nome`), ex.: "Atendente do
#   Orçamento" no lugar de "Atendente Pós-agendamento" (a CEVICO não muda).
class Crm::ResponderShadowJob < Crm::ResponderAgentJob
  FIELD = 'sombra_stage_ids'.freeze
  NAME_FIELD = 'nome'.freeze
  LABEL_KEY = :cevico_shadow_agent_label

  # chamado pelo CrmListener com os agentes já filtrados (ligados + caixa da conversa)
  def self.enqueue_observers(conversation, message, agents, owner_key)
    observers_for(conversation, agents, owner_key).each do |key, cfg|
      set(wait: delay_for(cfg)).perform_later(conversation.id, message.id, key)
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::ResponderShadowJob] observadores: #{e.message}"
  end

  # { 'atendente_pos' => cfg } dos agentes que observam a coluna do cartão (menos o dono)
  def self.observers_for(conversation, agents, owner_key)
    watching = agents.reject { |key, a| key == owner_key || Array(a[FIELD]).empty? }
    stage_id = watching.empty? ? nil : card_stage_id(conversation)
    return {} if stage_id.blank?

    watching.select { |_key, a| Array(a[FIELD]).map(&:to_i).include?(stage_id) }
  end

  # coluna do cartão do contato (a mesma conta do CrmListener#responder_owner_for)
  def self.card_stage_id(conversation)
    contact = conversation.contact
    contact && Crm::Contact.where(contact_id: contact.id).order(:updated_at).last&.stage_id
  end

  # mesma espera do dono (reply_delay_seconds, padrão 6 s, entre 3 e 30)
  def self.delay_for(cfg)
    secs = cfg['reply_delay_seconds'].to_i
    secs = CrmListener::DEFAULT_REPLY_DELAY unless secs.positive?
    secs.clamp(3, 30).seconds
  end

  def perform(conversation_id, trigger_message_id, agent_key)
    conversation = Conversation.find_by(id: conversation_id)
    return unless workable?(conversation)
    return if Crm::PartnerGuard.partner_conversation?(conversation)

    account = conversation.account
    cfg = agent_cfg(account, agent_key)
    return unless cfg['enabled'] == true
    # anti-picada: só a ÚLTIMA mensagem do cliente ganha nota
    return if last_incoming_id(conversation) != trigger_message_id

    @observer_key = agent_key
    Thread.current[LABEL_KEY] = cfg[NAME_FIELD].to_s.strip.presence
    run_shadow(account, conversation, cfg, agent_key, trigger_message_id)
  ensure
    Thread.current[LABEL_KEY] = nil
  end

  private

  # nome da conta para o agente (nota e registro do card); sem nome = o de sempre
  def agent_name(agent_key)
    Thread.current[LABEL_KEY] || super
  end

  # observador não abre tarefa de urgência: quem cuida da conversa é o dono da coluna
  def urgent_outside_window!(*); end

  # a nota DESTE agente para a mensagem (a do dono, se ele também estiver em sombra, não conta)
  def shadow_note_exists?(conversation, trigger_message_id)
    conversation.messages.where(message_type: :activity)
                .where("additional_attributes -> 'cevico_ia_shadow' ->> 'agent' = ?", @observer_key.to_s)
                .exists?(["additional_attributes -> 'cevico_ia_shadow' ->> 'trigger_message_id' = ?", trigger_message_id.to_s])
  end
end
