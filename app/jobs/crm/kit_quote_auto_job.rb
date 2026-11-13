# ⚡ ORÇAMENTO AUTOMÁTICO (LIFE, 12/11/2026): roda logo depois que o atendente disse "me dá uns instantes que eu já estou
# montando o seu orçamento" (ferramenta gerar_orcamento, Crm::ResponderTools).
#   pronto → manda o orçamento oficial (PDF + pergunta de fechamento, Crm::KitQuote::Delivery) e deixa nota para a equipe
#   falhou → avisa o cliente que o sistema do fornecedor está instável e que precisa de alguns minutos, e abre tarefa
#            URGENTE para o humano gerar pelo botão "Gerar orçamento" da conversa (sempre tem monitoramento humano)
#
# ⏱️ TIMER (Guilherme, 13/11): "me dá alguns instantes que já estou montando o seu orçamento… alguns minutos depois já chama
# a pessoa e manda o orçamento com a pergunta de fechamento". O orçamento é montado na hora (falha aparece cedo), mas só é
# ENVIADO quando completa a espera, contada do pedido. Espera = ai_config agents.<agente>.orcamento_espera_segundos
# (padrão 180 s; 0 = manda assim que fica pronto). Em 2 tempos: 1º job monta e agenda o 2º; o 2º só envia.
class Crm::KitQuoteAutoJob < ApplicationJob
  queue_as :default

  STATE_KEY = 'cevico_orcamento_auto'.freeze
  # espera curta antes de montar: só evita a cotação começar junto com a fala do atendente
  WAIT = 10.seconds
  DEFAULT_DELAY = 180 # segundos entre o "me dá uns instantes" e o envio
  MAX_DELAY = 15 * 60
  STALE = 10.minutes # marca "gerando/pronto" mais velha que (espera + isso) não segura mais (job morreu no meio)
  RUNNING = %w[gerando pronto].freeze
  INSTABILITY = 'Estou com uma instabilidade no sistema do fornecedor agora. Vou precisar de alguns minutos para preparar ' \
                'o seu orçamento, combinado?'.freeze
  TASK_REASON = 'Orçamento automático não saiu'.freeze

  def self.enqueue!(conversation, agent_key)
    mark!(conversation, 'status' => 'gerando', 'em' => Time.current.iso8601, 'espera' => delay_for(conversation.account, agent_key))
    Crm::JourneyLabel.bill_received!(conversation.contact) # cartão vai para "Orçamento a fazer"
    set(wait: WAIT).perform_later(conversation.id, agent_key.to_s)
  end

  # segundos de espera configurados para o agente (padrão 3 min)
  def self.delay_for(account, agent_key)
    cfg = CrmSetting.find_by(account: account)&.ai_config&.dig('agents', agent_key.to_s).to_h
    return DEFAULT_DELAY unless cfg.key?('orcamento_espera_segundos')

    cfg['orcamento_espera_segundos'].to_i.clamp(0, MAX_DELAY)
  end

  # está gerando ou esperando a hora de enviar (para a ferramenta não disparar duas vezes)
  def self.running?(conversation)
    state = (conversation.additional_attributes || {})[STATE_KEY].to_h
    RUNNING.include?(state['status']) &&
      Time.zone.parse(state['em'].to_s).to_i > (STALE + state['espera'].to_i.seconds).ago.to_i
  rescue ArgumentError
    false
  end

  def self.mark!(conversation, value)
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge(STATE_KEY => value) }
  end

  def perform(conversation_id, agent_key, quote_id = nil)
    @conversation = Conversation.find_by(id: conversation_id)
    return if @conversation.nil? || @conversation.contact.nil?

    @agent_key = agent_key
    return deliver_ready(quote_id) if quote_id

    result = Crm::KitQuote::AutoBuild.new(@conversation.account, @conversation.contact).call
    result.ok? ? hold_or_deliver(result.quote) : fallback(result)
  rescue StandardError => e
    Rails.logger.error "[Crm::KitQuoteAutoJob] #{e.class}: #{e.message}"
    fallback(Crm::KitQuote::AutoBuild::Result.new(status: :erro, motivo: "#{e.class}: #{e.message.truncate(120)}")) if @conversation
  end

  private

  def state
    (@conversation.reload.additional_attributes || {})[STATE_KEY].to_h
  end

  # pronto antes da hora: guarda e agenda o envio para quando a espera completar
  def hold_or_deliver(quote)
    current = state
    left = remaining_seconds(current)
    return deliver(quote) if left < 3

    self.class.mark!(@conversation, current.merge('status' => 'pronto', 'orcamento_id' => quote.id))
    note!("⏱️ Orçamento automático pronto (#{Crm::KitQuote::CardUpdate.new(quote).summary_text}). " \
          "Vai para o cliente em #{left.ceil} s, com a pergunta de fechamento.")
    self.class.set(wait: left.ceil.seconds).perform_later(@conversation.id, @agent_key, quote.id)
  end

  def remaining_seconds(current)
    asked = Time.zone.parse(current['em'].to_s)
    return 0 if asked.nil?

    (asked + current['espera'].to_i.seconds) - Time.current
  rescue ArgumentError
    0
  end

  # 2º tempo: a espera acabou. Não manda se a equipe já mandou outro orçamento ou se este foi para a lixeira.
  def deliver_ready(quote_id)
    quote = Crm::Quote.find_by(id: quote_id, contact_id: @conversation.contact_id)
    return if quote.nil? || quote.trashed? || quote.sent_at.present?
    return if state['orcamento_id'].to_i != quote.id # a conversa já pediu/recebeu outro

    if Crm::Quote.where(contact_id: quote.contact_id).where.not(id: quote.id).exists?(['sent_at > ?', quote.created_at])
      note!('⏱️ Orçamento automático não foi: a equipe já mandou outro orçamento para este cliente.')
      return self.class.mark!(@conversation, state.merge('status' => 'pulado'))
    end

    deliver(quote)
  end

  def deliver(quote)
    situacao = Crm::KitQuote::Delivery.new(quote, agent_key: @agent_key).call
    note!("⚡ Orçamento automático #{situacao == :enviado ? 'ENVIADO' : "gerado (#{situacao})"}: " \
          "#{Crm::KitQuote::CardUpdate.new(quote).summary_text}. Confira no Gerador de proposta → Orçamentos gerados.")
    self.class.mark!(@conversation, 'status' => situacao.to_s, 'em' => Time.current.iso8601, 'orcamento_id' => quote.id)
  end

  def fallback(result)
    say!(INSTABILITY) if @conversation.can_reply?
    Crm::HandoffTask.open!(
      account: @conversation.account, contact: @conversation.contact, conversation: @conversation, agent_key: @agent_key,
      motivo: "#{TASK_REASON} · gerar pelo botão Gerar orçamento da conversa", urgencia: 'alta',
      detalhes: "Motivo: #{result.motivo}\nO cliente já ouviu que o sistema do fornecedor está instável e que leva alguns minutos."
    )
    note!("⚠️ #{TASK_REASON}: #{result.motivo}. Tarefa urgente aberta para gerar na mão.")
    self.class.mark!(@conversation, 'status' => 'falhou', 'em' => Time.current.iso8601, 'motivo' => result.motivo.to_s)
  end

  def say!(text)
    @conversation.messages.create!(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :outgoing,
                                   content: text, additional_attributes: { 'cevico_ia_agent' => @agent_key })
  end

  def note!(text)
    @conversation.messages.create!(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :activity,
                                   private: true, content: text)
  end
end
