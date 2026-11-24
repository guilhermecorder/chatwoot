# 📨 ENVIO DO ORÇAMENTO PELO WHATSAPP (LIFE, 12/11/2026 · pedido do Guilherme): "envia quando estiver pronto e já faz
# uma pergunta de fechamento: é interessante para você fazer esse investimento agora?".
#
# Quem chama: o botão "Enviar pelo WhatsApp" da caixa do orçamento (Gerador de proposta) e a ferramenta
# `enviar_orcamento` do atendente (quando o cliente responde ao modelo "orçamento pronto").
#
#   Crm::KitQuote::Delivery.new(quote, sender: user).call
#     → :enviado     janela de 24 h aberta: proposta (PDF) + pergunta de fechamento; marca como enviada
#                    (o RESUMO em imagem NÃO vai no 1º envio — "é uma arma para usar depois", Guilherme 12/11:
#                    sai no follow-up de 3 dias pelo [resumo])
#     → :aguardando  janela fechada: manda o modelo life_orcamento_pronto ("Pode mandar"); o atendente envia quando ele responder
#     → :enviado_modelo  janela fechada e o modelo life_orcamento_pdf APROVADO (24/11, Guilherme: "precisamos enviar 100% dos
#                    orçamentos"): o PDF vai no cabeçalho do modelo, com a pergunta de fechamento. Não depende de o cliente
#                    responder ao "seu orçamento está pronto" — 4 orçamentos ficaram presos assim em 22/11.
#     → :sem_conversa / :sem_arquivos  (nada sai; a tela explica)
class Crm::KitQuote::Delivery
  READY_TEMPLATE = 'life_orcamento_pronto'.freeze
  READY_PREVIEW = 'Oi! Seu orçamento está pronto. Quando estiver por aí, me avisa que já te mando, ok?'.freeze
  PDF_TEMPLATE = 'life_orcamento_pdf'.freeze
  PDF_TEXT = "Oi, {{1}}! Aqui está o seu orçamento oficial de energia solar, com os valores atualizados.\n\n" \
             'Dá uma olhada com calma. Se fizer sentido para você e couber no seu planejamento, em 25 a 40 dias o sistema já ' \
             "fica instalado e gerando energia na sua casa.\n\nÉ possível para você fazer esse investimento agora?".freeze
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
    say!("Pronto#{", #{first}" if first.present?}! Aqui está o seu orçamento oficial de energia solar:")
    attach_message!(proposal_file, :file)
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

  # janela fechada: com o modelo do PDF aprovado, o orçamento vai direto; sem ele, o "Pode mandar" de antes
  def notify_ready!
    return send_pdf_template! if pdf_template_approved?

    notify_ready_old!
  end

  def pdf_template_approved?
    Array(@conversation.inbox&.channel.try(:message_templates)).any? do |t|
      t['name'] == PDF_TEMPLATE && t['status'].to_s.casecmp('approved').zero?
    end
  end

  def pdf_url
    host = ENV.fetch('FRONTEND_URL', nil)
    host && Rails.application.routes.url_helpers.rails_blob_url(proposal_file, host: host)
  end

  def send_pdf_template!
    url = pdf_url
    return notify_ready_old! if url.blank?

    first = @quote.contact&.name.to_s.split.first.presence || 'tudo bem'
    params = { 'name' => PDF_TEMPLATE, 'language' => 'pt_BR',
               'processed_params' => { 'body' => { '1' => first },
                                       'header' => { 'media_url' => url, 'media_type' => 'document',
                                                     'media_name' => proposal_file.filename.to_s } } }
    source = Crm::TemplateSource.new(@conversation.account, @conversation.inbox, @sender, params,
                                     PDF_TEXT.gsub('{{1}}', first), 'orcamento-pdf')
    return :sem_conversa if Crm::SendTemplateService.new(source: source, contact: @quote.contact).perform.nil?

    mark_sent!
    :enviado_modelo
  end

  # O cliente toca em "Pode mandar" e o atendente envia (enviar_orcamento).
  def notify_ready_old!
    params = { 'name' => READY_TEMPLATE, 'language' => 'pt_BR',
               'processed_params' => { 'body' => { '1' => @quote.contact&.name.to_s.split.first.presence || 'tudo bem' } } }
    source = Crm::TemplateSource.new(@conversation.account, @conversation.inbox, @sender, params, READY_PREVIEW, 'orcamento-pronto')
    return :sem_conversa if Crm::SendTemplateService.new(source: source, contact: @quote.contact).perform.nil?

    @quote.update!(payload: @quote.payload.merge(WAITING_KEY => Time.current.iso8601))
    :aguardando
  end
end
