# 📨 ENVIO DO ORÇAMENTO PELO WHATSAPP (LIFE, 12/11/2026 · pedido do Guilherme): "envia quando estiver pronto e já faz
# uma pergunta de fechamento: é interessante para você fazer esse investimento agora?".
#
# Quem chama: o botão "Enviar pelo WhatsApp" da caixa do orçamento (Gerador de proposta) e a ferramenta
# `enviar_orcamento` do atendente (quando o cliente responde ao modelo "orçamento pronto").
#
#   Crm::KitQuote::Delivery.new(quote, sender: user).call
#     → :enviado     janela de 24 h aberta: proposta (PDF) + resumo (JPG) + pergunta de fechamento; marca como enviada
#     → :aguardando  janela fechada: manda o modelo life_orcamento_pronto ("Pode mandar"); o atendente envia quando ele responder
#     → :sem_conversa / :sem_arquivos  (nada sai; a tela explica)
class Crm::KitQuote::Delivery
  READY_TEMPLATE = 'life_orcamento_pronto'.freeze
  READY_PREVIEW = 'Oi! Seu orçamento está pronto. Quando estiver por aí, me avisa que já te mando, ok?'.freeze
  WAITING_KEY = 'aguardando_envio'.freeze
  DELIVERY_STAMP = 'cevico_orcamento_enviado'.freeze

  attr_reader :conversation

  def initialize(quote, sender: nil, agent_key: nil)
    @quote = quote
    @sender = sender
    @agent_key = agent_key
    @conversation = latest_conversation
  end

  def self.closing_text(name)
    first = name.to_s.split.first.presence
    "#{first ? "#{first}, d" : 'D'}á uma olhada com calma. Se fizer sentido para você e couber no seu planejamento, em 25 a 40 dias " \
      "o sistema já fica instalado e gerando energia na sua casa.\n\nÉ interessante para você fazer esse investimento agora?"
  end

  def call
    return :sem_conversa if @conversation.nil?
    return :sem_arquivos if proposal_file.nil?
    return deliver! if @conversation.can_reply?

    notify_ready!
  end

  # janela aberta: os arquivos e a pergunta de fechamento
  def deliver!
    first = @quote.contact&.name.to_s.split.first
    say!("Pronto#{", #{first}" if first.present?}! Aqui está o seu orçamento de energia solar:")
    attach_message!(proposal_file, :file)
    attach_message!(summary_file, :image) if summary_file
    say!(self.class.closing_text(@quote.contact&.name))
    mark_sent!
    :enviado
  end

  private

  def latest_conversation
    contact = @quote.contact
    return nil if contact.nil?

    contact.conversations.joins(:inbox).where(inboxes: { channel_type: 'Channel::Whatsapp' })
           .order(last_activity_at: :desc, id: :desc).first
  end

  def proposal_file
    @proposal_file ||= files.find { |f| f.content_type == 'application/pdf' && !f.filename.to_s.match?(/justific/i) }
  end

  def summary_file
    @summary_file ||= files.find { |f| f.content_type.to_s.start_with?('image/') }
  end

  def files
    @files ||= @quote.files.to_a
  end

  def stamp
    { DELIVERY_STAMP => @quote.id, 'cevico_ia_agent' => @agent_key }.compact
  end

  def say!(text)
    @conversation.messages.create!(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :outgoing,
                                   content: text, sender: @sender, additional_attributes: stamp)
  end

  def attach_message!(attachment, type)
    message = @conversation.messages.new(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id,
                                         message_type: :outgoing, sender: @sender, additional_attributes: stamp)
    message.attachments.new(account_id: @conversation.account_id, file_type: type, file: attachment.blob)
    message.save!
  end

  def mark_sent!
    @quote.update!(sent_at: Time.current, payload: @quote.payload.except(WAITING_KEY))
    Crm::QuoteSent.call(@quote.contact, value: @quote.price)
  end

  # janela fechada: só modelo aprovado sai. O cliente toca em "Pode mandar" e o atendente envia (enviar_orcamento).
  def notify_ready!
    params = { 'name' => READY_TEMPLATE, 'language' => 'pt_BR',
               'processed_params' => { 'body' => { '1' => @quote.contact&.name.to_s.split.first.presence || 'tudo bem' } } }
    source = Crm::TemplateSource.new(@conversation.account, @conversation.inbox, @sender, params, READY_PREVIEW, 'orcamento-pronto')
    return :sem_conversa if Crm::SendTemplateService.new(source: source, contact: @quote.contact).perform.nil?

    @quote.update!(payload: @quote.payload.merge(WAITING_KEY => Time.current.iso8601))
    :aguardando
  end
end
