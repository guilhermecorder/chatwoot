# 💳 EXAME COM A FABI PAGO NO PIX (22/11/2026, pedido do Guilherme):
# o exame é o COMPROMISSO da conversa. Em clínica custa uns R$ 150; aqui, pagando ANTES no PIX,
# sai por R$ 29,90 e o horário fica reservado. Sem o PIX antecipado, na hora é R$ 70 (muita gente
# marca e falta, e o horário fica perdido). Chave PIX = CNPJ da loja.
#
# O fluxo é do SISTEMA (não depende do modelo lembrar):
#   1. o Atendente marca a visita COM EXAME (sábado, Fabi) → Crm::ResponderAgentJob#book! chama request!
#      → sai a mensagem do PIX (depois da fala do agente), o card vai pra coluna "PIX do exame"
#      e a conversa guarda o estado em additional_attributes['cevico_exame_pix'];
#   2. o robô de follow-up da coluna "PIX do exame" cutuca dentro da janela de 24 h (configuração da VPS);
#   3. chega a imagem lida como "comprovante" → Crm::MediaReadingJob chama receipt!:
#      valor R$ 29,90 no comprovante → etiqueta "exame-pago", card na coluna "Exame pago" (a automação da
#      coluna manda o evento de conversão), nota "PIX recebido" no agendamento, confirmação pra cliente
#      e tarefa pra equipe conferir no banco; valor diferente → só a tarefa pra equipe conferir.
module Otica::ExamPix # rubocop:disable Metrics/ModuleLength
  module_function

  STATE_KEY = 'cevico_exame_pix'.freeze
  STAMP_KEY = 'cevico_exame_pix_msg'.freeze
  PAID_LABEL = 'exame-pago'.freeze
  AGENT_KEY = 'exame_pix'.freeze
  PIX_KEY = '32.951.767/0001-92'.freeze
  PRICE = 29.90
  PRICE_FULL = 150
  PRICE_AT_DOOR = 70
  # a mensagem do PIX sai DEPOIS da fala do agente que confirmou o horário
  SEND_WAIT = 8.seconds
  WEEKDAYS = %w[domingo segunda terça quarta quinta sexta sábado].freeze
  AMOUNT = /29[,.]90/

  # ── 1. pedido do PIX (depois de marcar o exame) ──────────────────────────
  def enabled?(account)
    Otica::VirtualTryOn.otica?(account) && Otica::SalesTools.config(account)['exame_pix'] != 'desligado'
  end

  def request!(account:, conversation:, contact:, task:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return unless enabled?(account) && task && conversation

    state = state_of(conversation)
    return if state['status'] == 'pago' && state['task_id'] == task.id # remarcou um exame já pago: nada a cobrar

    deadline = deadline_for(task.due_at)
    already_asked = state['status'] == 'aguardando'
    save_state!(conversation, 'status' => 'aguardando', 'task_id' => task.id, 'contact_id' => contact.id,
                              'pedido_em' => state['pedido_em'] || Time.current.iso8601, 'prazo' => deadline.iso8601,
                              'horario' => task.due_at&.iso8601, 'valor' => PRICE)
    comment!(task, '💳 PIX do exame (R$ 29,90) pedido no WhatsApp; aguardando o comprovante')
    move!(account, contact, 'pix_exame')
    return if already_asked # remarcou antes de pagar: a chave já foi mandada

    send!(conversation, request_text(task.due_at, deadline))
    send!(conversation, PIX_KEY, wait: SEND_WAIT + 2.seconds) # a chave sozinha num balão, fácil de copiar
  rescue StandardError => e
    Rails.logger.error "[Otica::ExamPix] pedido do PIX na conversa #{conversation&.id}: #{e.class}: #{e.message}"
  end

  # 🤝 22/11 (Guilherme: "zero de cobrança… a gente está só ajudando… quando ela quiser, se ela quiser"):
  # o PIX é uma VANTAGEM opcional (preço menor + horário garantido), nunca cobrança nem ameaça.
  def request_text(starts_at, deadline)
    "Seu horário com a Fabi ficou marcado: #{when_label(starts_at)}.\n\n" \
      "Uma vantagem pra você: em clínica, esse exame costuma custar uns R$ #{PRICE_FULL}. Aqui, se você preferir " \
      "garantir o horário pagando antes pelo PIX, ele sai por R$ 29,90 (na hora, fica R$ #{PRICE_AT_DOOR}).\n\n" \
      "Esse valor de R$ 29,90 vale pro PIX feito até #{when_label(deadline)}. É só se fizer sentido pra você.\n\n" \
      'A chave PIX é o CNPJ da loja e vai na próxima mensagem. Se pagar, me manda o comprovante por aqui que eu ' \
      'deixo tudo certo pro seu exame.'
  end

  # 🤝 os lembretes da coluna "PIX do exame" (só benefício, zero cobrança) ficam no robô de follow-up da VPS:
  # OTICA/agente/ferramentas/aplica_exame_pix.rb

  # o PIX vale por até 24 h e no máximo até as 20 h da véspera do exame (nunca menos de 1 h antes)
  def deadline_for(starts_at) # rubocop:disable Metrics/AbcSize
    now = Time.current.in_time_zone(Otica::TZ.name)
    limit = now + 24.hours
    return limit.change(min: 0) + 1.hour if starts_at.nil?

    starts = starts_at.in_time_zone(Otica::TZ.name)
    eve = (starts.to_date - 1).in_time_zone(Otica::TZ.name).change(hour: 20)
    deadline = [limit, eve].min
    deadline = starts - 1.hour if deadline < now + 1.hour
    deadline.change(min: 0) == deadline ? deadline : deadline.change(min: 0) + 1.hour
  end

  # "sábado, 29/11, às 9h10" · "sexta, 28/11, às 20h"
  def when_label(time)
    t = time.in_time_zone(Otica::TZ.name)
    hour = t.min.zero? ? "#{t.hour}h" : "#{t.hour}h#{format('%02d', t.min)}"
    "#{WEEKDAYS[t.wday]}, #{t.strftime('%d/%m')}, às #{hour}"
  end

  # ── 3. comprovante ───────────────────────────────────────────────────────
  # chamado depois da leitura de cada imagem recebida; só age com PIX do exame aguardando
  def receipt!(message, attachment) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    conversation = message.conversation
    account = message.account
    return unless enabled?(account) && conversation

    media = attachment.meta&.dig('cevico_media') || {}
    return unless media['tipo'].to_s == 'comprovante'

    state = state_of(conversation)
    return unless %w[aguardando conferir].include?(state['status'])

    task = account.tasks.find_by(id: state['task_id'], canceled_at: nil)
    contact = account.contacts.find_by(id: state['contact_id']) || conversation.contact
    text = [media['texto'], media['descricao']].join(' ')
    return confirm!(account, conversation, contact, task, attachment) if text.match?(AMOUNT)

    save_state!(conversation, state.merge('status' => 'conferir', 'attachment_id' => attachment.id))
    team_task!(account, conversation, contact, 'Comprovante do exame com valor diferente',
               'Chegou um comprovante, mas não achei os R$ 29,90 nele. Confira no banco e confirme o horário do exame com a cliente.')
  rescue StandardError => e
    Rails.logger.error "[Otica::ExamPix] comprovante na conversa #{conversation&.id}: #{e.class}: #{e.message}"
  end

  def confirm!(account, conversation, contact, task, attachment)
    save_state!(conversation, state_of(conversation).merge('status' => 'pago', 'pago_em' => Time.current.iso8601,
                                                           'attachment_id' => attachment.id))
    contact.add_labels([PAID_LABEL])
    comment!(task, '✅ PIX do exame (R$ 29,90) recebido: comprovante na conversa. Conferir no banco.') if task
    move!(account, contact, 'exame_pago')
    horario = task&.due_at ? " #{when_label(task.due_at)}." : '.'
    send!(conversation, "Recebi o seu comprovante! O seu exame com a Fabi está reservado:#{horario}\n\nQualquer coisa, é só me chamar por aqui.",
          wait: 2.seconds)
    team_task!(account, conversation, contact, 'Conferir PIX do exame (R$ 29,90)',
               "Comprovante recebido e horário confirmado na conversa#{task&.due_at ? " (#{when_label(task.due_at)})" : ''}. Conferir no banco.")
  end

  # ── peças ────────────────────────────────────────────────────────────────
  def state_of(conversation)
    (conversation.reload.additional_attributes || {})[STATE_KEY].to_h
  end

  def save_state!(conversation, state)
    Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge(STATE_KEY => state) }
  end

  def move!(account, contact, key)
    stage = Otica::CrmBridge.stage_for(account, key)
    return if stage.nil?

    Crm::AttendanceReflector.move_contact_to_stage(account: account, contact: contact, new_stage: stage, create_if_missing: true)
  end

  def comment!(task, text)
    return if task.nil?

    entry = { 'kind' => 'exame_pix', 'at' => Time.current.iso8601(3), 'name' => 'Robô', 'text' => text }
    Task.where(id: task.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["comments = (CASE WHEN jsonb_typeof(comments) = 'array' THEN comments ELSE '[]'::jsonb END) || ?::jsonb", [entry].to_json]
    )
  end

  def team_task!(account, conversation, contact, motivo, detalhes)
    Crm::HandoffTask.open!(account: account, contact: contact, conversation: conversation, agent_key: 'atendente_agendamento',
                           motivo: motivo, detalhes: detalhes, urgencia: 'normal')
  end

  def send!(conversation, text, wait: SEND_WAIT)
    message = conversation.messages.new(account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
                                        content: Otica::TextSpacing.space(text),
                                        additional_attributes: { 'cevico_ia_agent' => AGENT_KEY, STAMP_KEY => true })
    message.cevico_send_wait = wait
    message.save!
    message
  end
end
