# Entra NA FRENTE do Webhooks::WhatsappEventsJob (prepend no initializer
# zz_cevico_calls) para desviar dois tipos de evento da Meta para o módulo
# de ligações: o campo `calls` (connect/terminate/statuses) e a resposta do
# paciente ao pedido de permissão (interactive call_permission_reply). Todo
# o resto segue o caminho normal (super).
module Cevico::WhatsappCallsWebhook
  def handle_message_events(channel, params)
    if cevico_calls_event?(params)
      return super unless cevico_calls_for_channel?(channel)

      Crm::Calls::WebhookService.new(channel: channel, value: cevico_webhook_value(params)).perform
      return
    end

    if cevico_permission_reply?(params)
      # sem super: a resposta cairia na conversa como mensagem "não suportada"
      Crm::Calls::PermissionReplyService.new(channel: channel, value: cevico_webhook_value(params)).perform
      return
    end

    super
  end

  private

  # eventos de chamada travam POR CHAMADA (não por remetente): connect,
  # statuses e terminate da mesma ligação chegam em sequência
  def contact_sender_id(params)
    return super unless cevico_calls_event?(params)

    value = cevico_webhook_value(params)
    call_id = value.dig(:calls, 0, :id) || value.dig(:statuses, 0, :id)
    call_id.present? ? "call:#{call_id}" : nil
  end

  def cevico_calls_event?(params)
    params.dig(:entry, 0, :changes, 0, :field).to_s == 'calls'
  end

  def cevico_permission_reply?(params)
    cevico_webhook_value(params).dig(:messages, 0, :interactive, :type).to_s == 'call_permission_reply'
  end

  # só desvia se o módulo está ligado para a conta e a caixa é a configurada
  def cevico_calls_for_channel?(channel)
    settings = Crm::Calls::Settings.new(channel.account)
    settings.enabled? && channel.inbox&.id == settings.inbox_id
  end

  def cevico_webhook_value(params)
    params.dig(:entry, 0, :changes, 0, :value) || {}
  end
end
