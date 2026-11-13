# ⚡ ORÇAMENTO AUTOMÁTICO (LIFE, 12/11/2026): roda logo depois que o atendente disse "já estou gerando o seu orçamento,
# em alguns segundos te mando" (ferramenta gerar_orcamento, Crm::ResponderTools).
#   pronto → manda o orçamento oficial (PDF + pergunta de fechamento, Crm::KitQuote::Delivery) e deixa nota para a equipe
#   falhou → avisa o cliente que o sistema do fornecedor está instável e que precisa de alguns minutos, e abre tarefa
#            URGENTE para o humano gerar pelo botão "Gerar orçamento" da conversa (sempre tem monitoramento humano)
class Crm::KitQuoteAutoJob < ApplicationJob
  queue_as :default

  STATE_KEY = 'cevico_orcamento_auto'.freeze
  # "uns 30 segundos": a cotação + o PDF levam ~20 a 40 s; a espera curta só evita chegar junto com a fala do atendente
  WAIT = 10.seconds
  STALE = 10.minutes # marca "gerando" mais velha que isso não segura mais (job morreu no meio)
  INSTABILITY = 'Estou com uma instabilidade no sistema do fornecedor agora. Vou precisar de alguns minutos para preparar ' \
                'o seu orçamento, combinado?'.freeze
  TASK_REASON = 'Orçamento automático não saiu'.freeze

  def self.enqueue!(conversation, agent_key)
    mark!(conversation, 'status' => 'gerando', 'em' => Time.current.iso8601)
    set(wait: WAIT).perform_later(conversation.id, agent_key.to_s)
  end

  # está gerando agora (para a ferramenta não disparar duas vezes)
  def self.running?(conversation)
    state = (conversation.additional_attributes || {})[STATE_KEY].to_h
    state['status'] == 'gerando' && Time.zone.parse(state['em'].to_s).to_i > STALE.ago.to_i
  rescue ArgumentError
    false
  end

  def self.mark!(conversation, value)
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge(STATE_KEY => value) }
  end

  def perform(conversation_id, agent_key)
    @conversation = Conversation.find_by(id: conversation_id)
    return if @conversation.nil? || @conversation.contact.nil?

    @agent_key = agent_key
    result = Crm::KitQuote::AutoBuild.new(@conversation.account, @conversation.contact).call
    result.ok? ? deliver(result.quote) : fallback(result)
  rescue StandardError => e
    Rails.logger.error "[Crm::KitQuoteAutoJob] #{e.class}: #{e.message}"
    fallback(Crm::KitQuote::AutoBuild::Result.new(status: :erro, motivo: "#{e.class}: #{e.message.truncate(120)}")) if @conversation
  end

  private

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
