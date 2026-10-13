class Macros::ExecutionService < ActionService
  def initialize(macro, conversation, user)
    super(conversation)
    @macro = macro
    @account = macro.account
    @user = user
    Current.user = user
  end

  # 🚧 Auditoria 10/2026 (#237): cerca dos parceiros também nos macros.
  # Macro NÃO é IA: é a pessoa clicando. Por isso a cerca aqui é mais estreita
  # que na automação nativa (revisão da Rodada 3):
  #   · na CAIXA DOS PARCEIROS (caixa 12) a equipe dela é quem pode falar com
  #     o paciente — o macro sai normalmente;
  #   · paciente de parceiro numa caixa da CEVICO: os passos que mandam
  #     mensagem/anexo ao paciente (ou a transcrição por e-mail) são pulados e
  #     fica uma NOTA PRIVADA na conversa dizendo o motivo (a pessoa vê na
  #     tela, não só no log); nota privada, etiqueta, responsável e status
  #     continuam valendo.
  PARTNER_BLOCKED_ACTIONS = %w[send_message send_attachment send_email_transcript].freeze
  PARTNER_BLOCKED_NOTE = 'Mensagem do macro não enviada: paciente de parceiro (Oftalmofácil). ' \
                         'Só a caixa do parceiro fala com ele.'.freeze

  def perform
    @macro.actions.each do |action|
      action = action.with_indifferent_access

      begin
        # a conferência da cerca fica dentro do rescue: se ela falhar, só este
        # passo cai (e é registrado), não o macro inteiro
        next if partner_blocked?(action[:action_name])

        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  # paciente de parceiro numa caixa da CEVICO + passo que fala com o paciente
  # = pula, registra no log e deixa uma nota privada (uma só por execução)
  def partner_blocked?(action_name)
    return false unless PARTNER_BLOCKED_ACTIONS.include?(action_name.to_s)

    @partner_blocked = partner_in_cevico_inbox? if @partner_blocked.nil?
    return false unless @partner_blocked

    Crm::PartnerGuard.block!("macro '#{@macro.name}' · #{action_name}", conversation: @conversation)
    leave_partner_blocked_note
    true
  end

  # a caixa dos parceiros é livre para a equipe dela; a cerca pega só o
  # paciente de parceiro conversando por uma caixa da CEVICO
  def partner_in_cevico_inbox?
    return false if Crm::PartnerGuard.partner_inbox?(@account, @conversation.inbox_id)

    Crm::PartnerGuard.partner_contact?(@conversation.contact)
  end

  def leave_partner_blocked_note
    return if @partner_note_left

    @partner_note_left = true
    add_private_note([PARTNER_BLOCKED_NOTE])
  end

  def assign_agent(agent_ids)
    agent_ids = agent_ids.map { |id| id == 'self' ? @user.id : id }
    super(agent_ids)
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @macro.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: 'macro.executed')
    WebhookJob.perform_later(webhook_url.first, payload)
  end
end

Macros::ExecutionService.include_mod_with('Macros::ExecutionService')
