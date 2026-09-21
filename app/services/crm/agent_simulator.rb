# 🧪 SIMULADOR DE AGENTES (rodada 188): ambiente SEGURO e dedicado para
# conversar com um agente respondedor como se você fosse o paciente, com a IA
# de verdade e o Roteiro atual — sem WhatsApp. Tudo acontece numa caixa
# interna do tipo API ("🧪 Simulador de agentes"), que não tem canal de
# envio: nem local nem em produção existe como uma mensagem escapar para um
# telefone. A resposta do agente fica na nota de sombra (mesmo formato da
# tela Sombra); o bate-papo da tela desenha as notas como balões.
class Crm::AgentSimulator
  INBOX_NAME = '🧪 Simulador de agentes'.freeze
  FAKE_PHONE = '+5511900000000'.freeze

  # objective (🎙️ rodada 195, só o Agente de Ligação): "Motivo da ligação" que a
  # tela manda — vira {{campanha_objetivo}} no prompt do simulador por texto
  def initialize(account:, agent_key:, objective: nil)
    @account = account
    @agent_key = agent_key.to_s
    @objective = objective.to_s.strip.first(300).presence
  end

  # conversa nova de teste (um "paciente de teste" fixo, sem telefone real)
  def start!
    contact = @account.contacts.find_by(phone_number: FAKE_PHONE) ||
              @account.contacts.create!(name: 'Paciente de teste', phone_number: FAKE_PHONE)
    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) { |ci| ci.source_id = "simulador-#{contact.id}" }
    Conversation.create!(
      account: @account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
      additional_attributes: { 'cevico_simulado' => true, 'cevico_simulado_agent' => @agent_key,
                               'cevico_simulado_objective' => @objective }.compact
    )
  end

  # troca o motivo numa conversa já aberta (a tela pode ajustar entre as falas)
  def objective!(conversation)
    attrs = conversation.additional_attributes || {}
    return if @objective.blank? || attrs['cevico_simulado_objective'] == @objective

    conversation.update!(additional_attributes: attrs.merge('cevico_simulado_objective' => @objective))
  end

  # uma fala do "paciente" → resposta do agente (IA de verdade) como nota de sombra
  def say!(conversation, text)
    message = conversation.messages.create!(
      account_id: @account.id, inbox_id: conversation.inbox_id, message_type: :incoming,
      content: text.to_s.strip, sender: conversation.contact
    )
    # simulador é sempre SOMBRA: as ferramentas (rodada 192) só simulam, nada escreve na Agenda
    result = Crm::ResponderAgentService.new(conversation: conversation, agent_key: @agent_key, live: false, simulation: true).call
    return { error: result[:error] } if result[:error]

    Crm::ResponderAgentJob.write_shadow_note!(conversation, @agent_key, result, message.id)
    { ok: true }
  end

  # a conversa como balões: paciente (incoming) e agente (notas de sombra)
  def transcript(conversation)
    conversation.messages.where(message_type: %i[incoming activity]).reorder(:id).filter_map do |m|
      if m.incoming?
        { role: 'patient', text: m.content.to_s, at: m.created_at.iso8601, id: m.id }
      elsif (shadow = m.additional_attributes&.[]('cevico_ia_shadow'))
        { role: 'agent', id: m.id, at: m.created_at.iso8601, messages: Array(shadow['mensagens']),
          meta: shadow.slice('etapa', 'agendar', 'agendamento', 'slot_valid', 'chamar_humano', 'cancelar', 'pausar', 'leitura', 'acoes') }
      end
    end
  end

  def self.simulated?(conversation)
    conversation.additional_attributes&.[]('cevico_simulado') == true
  end

  private

  # caixa interna do tipo API: sem provedor, nada sai dela
  def inbox
    @inbox ||= @account.inboxes.find_by(name: INBOX_NAME) || begin
      channel = Channel::Api.create!(account: @account)
      @account.inboxes.create!(name: INBOX_NAME, channel: channel)
    end
  end
end
