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

  # 🧹 item 413 (24/11): conversa de TESTE nunca conta em indicador. O teste do
  # Luna abriu ~400 conversas numa madrugada e o "Conversaram" do dia foi de
  # ~65 para 469. Toda contagem de conversa passa por aqui (a lente das fontes
  # já chama sozinha): a caixa do simulador fica fora, para sempre.
  def self.inbox_ids(account)
    account.inboxes.where(name: INBOX_NAME).pluck(:id)
  end

  def self.without(account, scope, column = 'conversations.inbox_id')
    ids = inbox_ids(account)
    ids.any? ? scope.where("#{column} NOT IN (?)", ids) : scope
  end

  # objective (🎙️ rodada 195, só o Agente de Ligação): "Motivo da ligação" que a
  # tela manda — vira {{campanha_objetivo}} no prompt do simulador por texto
  # script_version (22/09): 'v1' = Roteiro oficial, 'v2' = Roteiro paralelo em
  # teste. A conversa de teste nasce presa a uma versão (guardada nos atributos)
  # para dar para testar um, depois o outro, sem misturar.
  def initialize(account:, agent_key:, objective: nil, script_version: nil)
    @account = account
    @agent_key = agent_key.to_s
    @objective = objective.to_s.strip.first(300).presence
    @script_version = Crm::CevicoScript.normalize_version(script_version)
  end

  # conversa nova de teste (um "paciente de teste" fixo, sem telefone real)
  def start!
    contact = @account.contacts.find_by(phone_number: FAKE_PHONE) ||
              @account.contacts.create!(name: 'Paciente de teste', phone_number: FAKE_PHONE)
    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) { |ci| ci.source_id = "simulador-#{contact.id}" }
    conversation = Conversation.create!(
      account: @account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
      additional_attributes: { 'cevico_simulado' => true, 'cevico_simulado_agent' => @agent_key,
                               'cevico_simulado_objective' => @objective,
                               'cevico_simulado_script' => @script_version }.compact
    )
    self.class.archive!(conversation)
    conversation
  end

  # troca o motivo numa conversa já aberta (a tela pode ajustar entre as falas)
  # (Rodada 4 da auditoria: grava pelo Cevico::AttributeMerge, como todo mundo)
  def objective!(conversation)
    attrs = conversation.additional_attributes || {}
    return if @objective.blank? || attrs['cevico_simulado_objective'] == @objective

    Cevico::AttributeMerge.merge!(conversation) { |fresh| fresh.merge('cevico_simulado_objective' => @objective) }
  end

  # uma fala do "paciente" → resposta do agente (IA de verdade) como nota de sombra
  # model (item 399): motor escolhido NA TELA DO TESTE para esta fala (Claude ou
  # ChatGPT); vazio = o que o cartão do agente usa. Não grava nada no agente.
  # consultant (item 414): consultor superior só deste teste ({ 'model' =>, 'mode' => });
  # vazio = o que o cartão do agente tem (desligado, na maioria).
  def say!(conversation, text, model: nil, consultant: nil)
    reply!(conversation, hear!(conversation, text), model: model, consultant: consultant)
  end

  # ⏱️ item 414: a mesma fala em SEGUNDO PLANO. A chamada da tela morre em 15 s
  # (limite do servidor para telas) e uma resposta com várias voltas de
  # ferramenta, ou com consulta ao superior, não cabe. Aqui a fala entra, a
  # resposta roda na fila (Crm::AgentSimulatorJob) e a tela busca o resultado.
  def say_later!(conversation, text, model: nil, consultant: nil)
    message = hear!(conversation, text)
    self.class.pending!(conversation, message.id)
    Crm::AgentSimulatorJob.perform_later(conversation.id, message.id, @agent_key, model.to_s.presence, consultant.presence)
    { ok: true, pending: true }
  rescue StandardError => e
    self.class.archive!(conversation)
    raise e
  end

  # a fala do paciente entra na conversa de teste
  def hear!(conversation, text)
    # 🗄️ item 412: a conversa de teste vive RESOLVIDA; abre em silêncio só durante a fala
    # (sem o "reabrir" do paciente, que zeraria as pausas da IA) e volta a arquivar no fim
    self.class.silent_status!(conversation, :open)
    conversation.messages.create!(
      account_id: @account.id, inbox_id: conversation.inbox_id, message_type: :incoming,
      content: text.to_s.strip, sender: conversation.contact
    )
  end

  # a resposta do agente a uma fala que já está na conversa
  def reply!(conversation, message, model: nil, consultant: nil)
    # simulador é sempre SOMBRA: as ferramentas (rodada 192) só simulam, nada escreve na Agenda
    result = Crm::ResponderAgentService.new(conversation: conversation, agent_key: @agent_key, live: false, simulation: true,
                                            script_version: self.class.script_version(conversation), model_override: model,
                                            consultant_override: consultant).call
    return { error: result[:error] } if result[:error]

    Crm::ResponderAgentJob.write_shadow_note!(conversation, @agent_key, result, message.id)
    { ok: true }
  ensure
    self.class.archive!(conversation)
  end

  # a conversa como balões: paciente (incoming) e agente (notas de sombra)
  def transcript(conversation)
    conversation.messages.where(message_type: %i[incoming activity]).reorder(:id).filter_map do |m|
      if m.incoming?
        { role: 'patient', text: m.content.to_s, at: m.created_at.iso8601, id: m.id }
      elsif (shadow = m.additional_attributes&.[]('cevico_ia_shadow'))
        { role: 'agent', id: m.id, at: m.created_at.iso8601, messages: Array(shadow['mensagens']),
          meta: shadow.slice('etapa', 'agendar', 'agendamento', 'slot_valid', 'chamar_humano', 'cancelar', 'pausar', 'leitura', 'acoes',
                             'modelo', 'reserva', 'consultor') }
      end
    end
  end

  # 🗄️ item 412 (24/11): teste do simulador não aparece em "Abertas" para quem atende.
  # Troca o status direto na coluna: sem aviso "conversa resolvida", sem webhook, sem
  # automação de conversa resolvida (é só uma caixa interna de teste).
  def self.archive!(conversation)
    silent_status!(conversation, :resolved)
  end

  def self.silent_status!(conversation, status)
    return if conversation.blank? || conversation.status.to_s == status.to_s

    conversation.update_columns(status: Conversation.statuses.fetch(status.to_s), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # ── ⏱️ item 414: fala em segundo plano ───────────────────────────────────
  # O estado fica no Redis por 10 min: { 'message_id' =>, 'status' => 'pendente' |
  # 'pronto' | 'erro', 'error' => }. A tela pergunta até sair de 'pendente'.
  PENDING_KEY = 'cevico:simulador:fala:%<id>s'.freeze
  PENDING_TTL = 10.minutes

  # Há quem atenda a fila do teste AGORA? Sem um Sidekiq vivo ouvindo a fila
  # (processo parado, ambiente local só com o servidor de telas) a fala ficaria
  # esperando para sempre: aí o controlador responde na hora, como sempre fez.
  def self.background_ready?
    return true unless ActiveJob::Base.queue_adapter_name.to_s == 'sidekiq'

    queue = Crm::AgentSimulatorJob.queue_name.to_s
    Sidekiq::ProcessSet.new.any? { |process| Array(process['queues']).include?(queue) }
  rescue StandardError => e
    Rails.logger.warn "[Crm::AgentSimulator] fila do teste: #{e.message}"
    false
  end

  def self.pending!(conversation, message_id)
    write_status(conversation, 'message_id' => message_id, 'status' => 'pendente')
  end

  def self.finish!(conversation, message_id, error: nil)
    write_status(conversation, { 'message_id' => message_id, 'status' => error ? 'erro' : 'pronto', 'error' => error }.compact)
  end

  def self.write_status(conversation, payload)
    Redis::Alfred.set(format(PENDING_KEY, id: conversation.id), payload.to_json, ex: PENDING_TTL.to_i)
  end

  # { pending: true|false, error: 'texto' | nil } da última fala em segundo plano
  def self.status(conversation)
    raw = Redis::Alfred.get(format(PENDING_KEY, id: conversation.id))
    data = raw.present? ? JSON.parse(raw) : {}
    { pending: data['status'] == 'pendente', error: data['status'] == 'erro' ? data['error'].to_s : nil }
  rescue StandardError
    { pending: false, error: nil }
  end

  def self.simulated?(conversation)
    conversation.additional_attributes&.[]('cevico_simulado') == true
  end

  # versão do Roteiro presa à conversa de teste ('v1' quando nasceu antes disso existir)
  def self.script_version(conversation)
    Crm::CevicoScript.normalize_version(conversation.additional_attributes&.[]('cevico_simulado_script'))
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
