# 🔁 ATENDIMENTO SEM BURACO (23/11/2026): camada ATIVA da pausa com prazo do
# Atendente IA do WhatsApp (regras em Crm::ResponderPause).
#
# É agendado para o fim do prazo toda vez que a pausa nasce ou é renovada:
#   · alguém da equipe escreveu (pausa humano_assumiu) → N min + 5 s depois;
#   · a IA chamou a equipe e o paciente escreveu → N min + 5 s depois.
# Na hora, confere se a pausa AINDA é a mesma e já venceu. Se alguém da equipe
# escreveu de novo, a hora da pausa mudou: este job sai sem fazer nada (o job
# agendado pela mensagem nova cuida). Se venceu: limpa a pausa, deixa a nota
# para a equipe e, se a última fala da conversa é do paciente e ficou sem
# resposta, devolve a conversa ao agente dono da coluna, igual ao resgate.
# Pausa pela chavinha, teto diário e urgência clínica não vencem.
# Leve (sem IA): roda na fila comum, não ocupa a cápsula da IA.
class Crm::ResponderResumeJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return unless Crm::ResponderPause.state_of(conversation)['paused']

    cfg = Crm::ResponderPause.ai_config(conversation)
    state = Crm::ResponderPause.refresh!(conversation, cfg)
    return if state['paused'] # ainda vale: a equipe escreveu de novo, ou o prazo é outro

    hand_back(conversation, cfg)
  end

  private

  # a última fala (não privada) é do paciente e ninguém respondeu? volta ao agente
  def hand_back(conversation, cfg)
    return unless conversation.open?

    last = conversation.messages.where(private: false, message_type: %i[incoming outgoing]).order(:id).last
    return unless last&.incoming?
    # 🚧 cerca dos parceiros: paciente do Oftalmofácil nunca volta para a IA
    return if Crm::PartnerGuard.partner_conversation?(conversation)

    agents = live_agents(cfg, conversation)
    key = agents.empty? ? nil : CrmListener.instance.send(:responder_owner_for, conversation, agents)
    return if key.blank? # coluna sem agente dono (ou fora da janela ao vivo): fica com a equipe

    Crm::ResponderAgentJob.perform_later(conversation.id, last.id, key)
    log(conversation, key)
  end

  def live_agents(cfg, conversation)
    ((cfg || {})['agents'] || {}).slice(*CrmListener::RESPONDER_KEYS).select do |_key, a|
      a['enabled'] == true && Crm::ResponderAgentJob.live_mode?(a) && Array(a['inbox_ids']).map(&:to_i).include?(conversation.inbox_id)
    end
  end

  # registro no card do agente (Automações → Agentes de IA), como o resgate
  def log(conversation, key)
    event = { 'at' => Time.current.iso8601, 'type' => 'religou', 'conversation_id' => conversation.display_id,
              'contact' => conversation.contact&.name.to_s.truncate(40),
              'note' => 'pausa venceu sem resposta da equipe: devolvi a mensagem do paciente ao agente' }
    Cevico::SettingMerge.merge_key!(conversation.account, :ai_config, "#{key}_state") do |agent_state|
      agent_state['events'] = [event] + Array(agent_state['events']).first(Crm::ResponderAgentJob::LOG_CAP - 1)
      agent_state
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderResumeJob] registro: #{e.message}"
  end
end
