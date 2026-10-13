# DESPACHANTE (item 168): manda os envios da fila cuja hora chegou, dentro
# da janela da conta, respeitando etiquetas de silêncio e o teto diário.
# Modelo aprovado sai pelo Crm::SendTemplateService (chega com a janela de
# 24h fechada); texto livre só sai se a conversa ainda aceita resposta.
# Envio pendente há mais de 12 h vira "expirou" (ninguém aprovou / hora
# passou demais) — nunca manda "sua cirurgia é amanhã" dois dias depois.
class Crm::Journey::Dispatcher
  TZ = Crm::Journey::Settings::TZ
  EXPIRE_AFTER = 12.hours
  # mensagens amarradas a uma data (consulta da Agenda / cirurgia do hub) — #426
  DATED_KINDS = %w[surgery appointment].freeze
  TEXT_WINDOW_CLOSED = 'A janela de 24h desta conversa está fechada — só mensagem modelo chega.'.freeze

  attr_reader :account, :now, :settings

  def initialize(account:, now: nil)
    @account = account
    @now = (now || TZ.now).in_time_zone(TZ)
    @settings = Crm::Journey::Settings.new(account)
  end

  # devolve { sent:, failed:, skipped:, expired:, reconciled: }
  def perform
    result = Hash.new(0)
    result[:expired] = expire_stale!
    # 🛡️ R3 (#45): envio "enviado" que a Meta recusou vira 'failed' com o erro
    # da Meta; envio preso em 'sending' também (Crm::Journey::Reconciler)
    result[:reconciled] = Crm::Journey::Reconciler.new(account: account, now: now).perform
    return result unless settings.within_hours?(now)

    budget = settings.daily_cap - sent_today
    Crm::JourneySend.where(account: account).due(now).includes(:journey_message, :contact, :source).find_each do |send|
      break if budget <= 0

      outcome = dispatch(send)
      result[outcome] += 1
      budget -= 1 if outcome == :sent
    end
    result
  end

  # envia UM (a aprovação manual também passa aqui). Devolve :sent | :failed |
  # :skipped | :busy. 🔒 R3 (#21/#412): PEGA o envio no banco de forma atômica
  # (fila/aprovação → 'sending'); quem não pegou devolve :busy e não manda —
  # dois cliques, duas abas, "Aprovar todos" + "Aprovar" ou clique + cron
  # nunca mandam o mesmo balão duas vezes.
  def dispatch(send)
    send.claim!(from: Crm::JourneySend::CLAIMABLE) ? dispatch_claimed(send) : :busy
  end

  # "Reenviar" da tela: pega direto de falhou/pulado/expirou (sem passar por
  # 'queued', para o cron não pegar o mesmo envio no meio) e manda
  def retry(send)
    return :busy unless send.claim!(from: Crm::JourneySend::RETRYABLE)

    send.update!(error: nil, scheduled_for: now)
    dispatch_claimed(send)
  end

  # manda um envio que JÁ está pego ('sending')
  def dispatch_claimed(send)
    message = send.journey_message
    contact = send.contact
    blocked = blocked_reason(send, message, contact)
    return finish(send, blocked[0], blocked[1]) if blocked

    inbox = message.inbox || account.inboxes.find_by(id: message.inbox_id)
    return finish(send, 'failed', 'Escolha a caixa do WhatsApp da mensagem') if inbox.nil?

    deliver(send, message, inbox, contact)
  rescue StandardError => e
    Rails.logger.error("[CEVICO jornada] envio #{send.id}: #{e.message}")
    finish(send, 'failed', e.message.truncate(300))
  end

  # 🛡️ R3 (#46): mensagem que usa {{hora}}/{{medico}}/{{procedimento}} com a
  # fonte sem esse dado (ou paciente sem nome) é PULADA com o motivo — nunca
  # vai em branco para a Meta. O teste usa dados fictícios, não passa por aqui.
  # [status, motivo] do primeiro bloqueio que pegar; nil quando pode sair
  def blocked_reason(send, message, contact)
    blocker_for(message, contact) || quiet_blocker(send, message, contact) || followup_blocker(send) || event_blocker(send) || variable_blocker(send)
  end

  # etiqueta de silêncio (nao_perturbe / lista da conta). O TESTE ignora: o
  # celular de teste da equipe carrega nao_perturbe de propósito (#416)
  def quiet_blocker(send, message, contact)
    return nil if send.test? || !message.respect_quiet || !settings.quiet?(contact.label_list)

    ['skipped', 'Paciente pediu para não receber mensagens']
  end

  def variable_blocker(send)
    why = !send.test? && Crm::Journey::Variables.missing_reason(send.journey_message, send.source, send.contact, settings, followup: send.followup?)
    why && ['skipped', why]
  end

  # texto final que o paciente lê (modelo com as variáveis trocadas)
  def preview_text(message, values, followup: false) # rubocop:disable Metrics/CyclomaticComplexity
    return Crm::Journey::Variables.substitute(message.text, values) if message.mode == 'text' && !followup

    params, preview = followup ? [message.followup_template_params, message.followup_preview] : [message.template_params, message.message_preview]
    body = (params || {}).dig('processed_params', 'body') || {}
    base = preview.presence || message.name
    text = body.reduce(base) { |acc, (k, v)| acc.gsub("{{#{k}}}", Crm::Journey::Variables.substitute(v, values)) }
    text.gsub('{{contact.name}}', values['nome'].to_s)
  end

  # 🛡️ auditoria 10/10 (#426): o planejador olha a consulta/cirurgia só na
  # hora de PLANEJAR; se ela foi cancelada, remarcada ou já passou até a hora
  # de MANDAR, o envio é pulado. Vale para o envio original (o reforço já
  # tinha a checagem dele) e para o "reenviar" da tela. Devolve
  # ['skipped', motivo] ou nil quando pode sair. O reforço já é conferido pelo
  # Followup; o envio de teste ("Testar no meu número") não é para paciente.
  def event_blocker(send)
    return nil if send.followup? || send.test?

    why = dated_event_blocker(send)
    why && ['skipped', why]
  end

  # motivo para NÃO reenviar pela tela (nil = pode): além das checagens do
  # evento, envio planejado para OUTRO DIA não sai hoje com data velha. Olha o
  # dia em que o envio ia sair (scheduled_for), não o dia da consulta — assim
  # "3 dias depois" reenviado no mesmo dia passa, e "é amanhã" reenviado no
  # dia da consulta é recusado aqui, com o motivo certo e o "Expirou" intacto.
  def retry_blocker(send)
    message = send.journey_message
    return nil if send.test?
    return nil unless message && DATED_KINDS.include?(message.kind)

    send_day = send.scheduled_for.in_time_zone(TZ).to_date
    return "Esta mensagem era para #{send_day.strftime('%d/%m')} e o dia já passou" if send_day < now.to_date

    dated_event_blocker(send)
  end

  private

  # dia da consulta/cirurgia que o planejador tinha em mente ao criar o envio
  def planned_day(send)
    send.scheduled_for.in_time_zone(TZ).to_date - send.journey_message.offset_days
  end

  def dated_event_blocker(send)
    message = send.journey_message
    return nil unless message && DATED_KINDS.include?(message.kind)

    case send.source
    when Task then task_event_blocker(send, send.source)
    when Crm::OftalmofacilSurgery then surgery_event_blocker(send, send.source)
    else 'A consulta ou cirurgia deste envio não existe mais'
    end
  end

  def task_event_blocker(send, task)
    return 'A consulta foi cancelada' if task.canceled_at.present?
    return 'A consulta foi arquivada' if task.archived_at.present?
    return 'O paciente já avisou que não vem' if task.declined_at.present?

    at = task.due_at&.in_time_zone(TZ)
    moved_or_passed(send, 'consulta', at&.to_date, at)
  end

  def surgery_event_blocker(send, surgery)
    return 'A cirurgia não está mais agendada' if surgery.status_kind != 'agendada'

    # sem hora no hub, só conta como passada quando o dia inteiro passou
    at = surgery.hour_hhmm ? surgery.local_time : surgery.surgery_date&.in_time_zone(TZ)&.end_of_day
    moved_or_passed(send, 'cirurgia', surgery.surgery_date, at)
  end

  # a data mudou depois do planejamento, ou (mensagem do dia / da véspera) o
  # horário já passou — mensagem de DEPOIS do evento (offset positivo) não entra.
  # Regra: mensagem do dia ou da véspera só sai ANTES da hora da consulta;
  # por isso o horário de envio ("at") precisa vir antes da primeira consulta.
  def moved_or_passed(send, what, date, at)
    return "A #{what} está sem data" if date.nil?
    return "A #{what} foi remarcada para outro dia" if date != planned_day(send)
    if send.journey_message.offset_days <= 0 && at <= now
      return "O horário da #{what} já passou (mensagem do dia ou da véspera só sai antes da hora da #{what})"
    end

    nil
  end

  def deliver(send, message, inbox, contact)
    # 🧪 teste ("Testar no meu número") sai com dados fictícios, nunca com a
    # cirurgia/consulta de um paciente real (#416)
    values = send.test? ? Crm::Journey::Variables.sample(settings) : Crm::Journey::Variables.build(send.source, contact, settings)
    conversation = deliver_by_kind(send, message, inbox, contact, values)
    return finish(send, 'failed', @last_error || 'O envio não saiu (veja a caixa e o modelo)') if conversation.nil?

    # guarda o id da Message para reconferir depois se a Meta recusou (Crm::Journey::Reconciler)
    send.update!(status: 'sent', sent_at: Time.current, conversation: conversation,
                 variables: values.merge(Crm::JourneySend::MESSAGE_ID_KEY => @last_message_id).compact,
                 preview: preview_text(message, values, followup: send.followup?), error: nil)
    :sent
  end

  # porta única do modelo; o serviço diz qual mensagem ELE criou (não "a última
  # da conversa", que podia ser a de um atendente no mesmo instante)
  def deliver_template(source, contact)
    svc = Crm::SendTemplateService.new(source: source, contact: contact)
    svc.perform.tap { @last_message_id = svc.message&.id }
  end

  # 🔁 item 288: o reforço sai SEMPRE como mensagem modelo (a do reforço)
  def deliver_by_kind(send, message, inbox, contact, values)
    return send_followup(send, message, inbox, contact, values) if send.followup?

    message.mode == 'text' ? send_text(message, inbox, contact, values) : send_template(message, inbox, contact, values)
  end

  def send_followup(send, message, inbox, contact, values)
    params = Crm::Journey::Variables.apply(message.followup_template_params, values)
    source = Crm::TemplateSource.new(account, inbox, nil, params, message.followup_preview,
                                     "Reforço #{send.followup_number} · #{message.name}")
    deliver_template(source, contact)
  end

  # o reforço só sai se AINDA faz sentido (vale também para "reenviar" na tela)
  def followup_blocker(send)
    return nil unless send.followup?

    why = Crm::Journey::Followup.new(account: account, now: now).blocker_for(send)
    why && ['skipped', why]
  end

  # [status, motivo] quando o envio não deve sair; nil quando pode
  def blocker_for(message, contact)
    return ['skipped', 'Mensagem desligada'] unless message&.active?
    return ['skipped', 'Paciente sem telefone'] if contact.nil? || contact.phone_number.blank?
    # 🚧 item 231 (cerca dos parceiros)
    return ['skipped', 'Paciente de parceiro do Oftalmofácil: sem mensagens automáticas'] if Crm::PartnerGuard.partner_contact?(contact)

    nil
  end

  def sent_today
    day_start = TZ.local(now.year, now.month, now.day)
    Crm::JourneySend.where(account: account, status: 'sent', sent_at: day_start..now).count
  end

  def expire_stale!
    Crm::JourneySend.where(account: account, status: %w[queued pending_review])
                    .where(scheduled_for: ...(now - EXPIRE_AFTER))
                    .update_all(status: 'expired', error: 'A hora passou sem envio', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def finish(send, status, error)
    send.update!(status: status, error: error)
    status.to_sym
  end

  def send_template(message, inbox, contact, values)
    params = Crm::Journey::Variables.apply(message.template_params, values)
    source = Crm::TemplateSource.new(account, inbox, nil, params, message.message_preview, message.name)
    deliver_template(source, contact)
  end

  def send_text(message, inbox, contact, values)
    finder = Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: contact.phone_number.to_s.delete('^0-9'),
                                                name: contact.name, contact: contact)
    conversation = finder.conversation
    unless conversation.can_reply?
      @last_error = TEXT_WINDOW_CLOSED
      return nil
    end
    text = Crm::Journey::Variables.substitute(message.text, values)
    created = conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing,
                                            content: text, additional_attributes: { 'cevico_journey' => message.id })
    @last_message_id = created.id
    conversation
  end
end
