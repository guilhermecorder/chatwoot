# 🧭 MOTOR POR COLUNA DO CRM (23/11/2026): o MESMO atendente e o MESMO Roteiro,
# mas o modelo de IA que responde muda conforme a COLUNA em que o card do
# paciente está. Exemplo do Guilherme: recepção em "Novos Contatos" com um
# ChatGPT barato; a partir de "Envio de Orçamento", o Claude.
#
# A config mora em ai_config['agents'][agente]['stage_models']:
#   { '1' => 'gpt-6-luna', '2' => 'claude-sonnet-5', 'sem_card' => 'gpt-6-luna' }
# Chave = id da coluna (texto) ou 'sem_card' (paciente que ainda não tem card).
# Coluna sem escolha = o "Modelo de IA" do cartão do atendente, como sempre.
#
# Quem decide a coluna é a mesma regra que decide o DONO da conversa
# (CrmListener#responder_owner_for): o card mais recente do contato.
# Se a chave do fornecedor do modelo escolhido sumir, o atendente cai no modelo
# do cartão (nunca fica mudo); e se o motor falhar na hora, vale a reserva de
# sempre (Crm::ResponderAgentService).
module Crm::StageEngine
  module_function

  CONFIG_KEY = 'stage_models'.freeze
  NO_CARD = 'sem_card'.freeze

  # { 'id da coluna' | 'sem_card' => modelo } do agente (sempre um Hash)
  def config(agent_config)
    raw = agent_config.is_a?(Hash) ? agent_config[CONFIG_KEY] : nil
    raw.is_a?(Hash) ? raw : {}
  end

  # coluna do card mais recente do paciente desta conversa (nil = sem card)
  def stage_id_for(conversation)
    contact_id = conversation&.contact_id
    return nil if contact_id.blank?

    Crm::Contact.where(contact_id: contact_id).order(:updated_at).last&.stage_id
  end

  # chave da config para esta conversa: '12' ou 'sem_card'
  def slot_for(conversation)
    stage_id_for(conversation)&.to_s || NO_CARD
  end

  # o modelo escolhido para a coluna desta conversa, ou nil (= o do cartão)
  def model_for(conversation, agent_config)
    choices = config(agent_config)
    return nil if choices.empty?

    choices[slot_for(conversation)].to_s.strip.presence
  end

  # colunas do atendente na ordem do funil (+ "sem card" quando ele atende
  # contato novo), cada uma com o modelo escolhido (nil = o do cartão)
  def rows(account, agent_config)
    agent_config = {} unless agent_config.is_a?(Hash)
    choices = config(agent_config)
    list = Crm::Stage.joins(:pipeline)
                     .where(crm_pipelines: { account_id: account.id }, id: Array(agent_config['stage_ids']).map(&:to_i))
                     .order('crm_pipelines.id', :position)
                     .map { |stage| { slot: stage.id.to_s, name: stage.name } }
    list.unshift({ slot: NO_CARD, name: 'Sem card ainda (contato novo)' }) if agent_config['no_card'] == true
    list.map { |row| row.merge(model: choices[row[:slot]].to_s.strip.presence) }
  end

  # 🧭 item 405: o motor da coluna para QUEM NÃO É o atendente (o lembrete com
  # IA do follow-up): procura, entre os atendentes do WhatsApp, quem escolheu
  # um modelo para a coluna em que este paciente está. nil = ninguém escolheu.
  def owner_model_for(conversation, ai_config)
    agents = ai_config.is_a?(Hash) ? ai_config['agents'] : nil
    return nil unless agents.is_a?(Hash)

    # 📥 item 416: caixa com motor próprio vence a coluna
    Crm::LlmEngines::OPENAI_AGENT_KEYS.each do |key|
      own = Crm::InboxEngine.entry_for(conversation, agents[key])&.dig('model').to_s.strip
      return own if own.present?
    end

    slot = slot_for(conversation)
    Crm::LlmEngines::OPENAI_AGENT_KEYS.each do |key|
      chosen = config(agents[key])[slot].to_s.strip
      return chosen if chosen.present?
    end
    nil
  end

  # limpa o que chegou da tela: só colunas que o agente lê (+ sem_card se ele
  # atende quem não tem card) e só modelo reconhecido; em branco = sai da lista
  def sanitize(raw, agent_config)
    allowed = Array(agent_config['stage_ids']).map { |id| id.to_i.to_s }
    allowed << NO_CARD if agent_config['no_card'] == true
    (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h).each_with_object({}) do |(slot, model), clean|
      slot = slot.to_s
      model = model.to_s.strip
      next if model.blank? || allowed.exclude?(slot)

      clean[slot] = model
    end
  end
end
