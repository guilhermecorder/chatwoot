# 🔐 Rodada 4 da auditoria (10/2026, achado #119) — "o formulário do link
# limpo só grava no cadastro certo". Três caminhos para a resposta pública:
#
#   (1) link ASSINADO (enviado pelo sistema, token com o paciente): a resposta
#       já é confiável e cai direto no cadastro — nada muda aqui.
#   (2) link LIMPO com telefone de cadastro que JÁ EXISTE: a resposta nasce
#       "não confirmada" (paliativo da Rodada 1) e o sistema manda um CÓDIGO
#       de 6 dígitos pela conversa em que o paciente já fala com a clínica
#       (WhatsApp com mensagem dele nas últimas 24 h — sem custo de modelo).
#       A página pede o código; acertou → a resposta vira confirmada e, se o
#       paciente ainda não tem card no funil, ganha o card em "Agendamento de
#       Consulta". Sem conversa na janela, sem código válido em 10 min ou
#       paciente de parceiro (cerca) → a resposta FICA "não confirmada" e o
#       cadastro nunca muda.
#   (3) telefone DESCONHECIDO: o paciente é criado SEM card (não entra na
#       coluna de agendamento nem nos indicadores de etapa) com a marca
#       `cevico_form_pending`; ganha card quando escreve no WhatsApp (o
#       CrmListener cria o card da conversa nova, como sempre). Para a equipe
#       ENXERGAR esse lead, abre uma tarefa leve "ligar e confirmar" (no máximo
#       PENDING_TASKS_PER_DAY por formulário por dia). Teto diário GLOBAL de
#       cadastros novos por formulário (Crm::Form::DAILY_NEW_CONTACTS) com
#       tarefa 🔴 para o administrador quando estoura.
#
# O código mora SÓ no Redis (SET NX, 10 min, 5 tentativas) — nunca no HTML
# nem no JSON da página. No máximo CODES_PER_HOUR códigos por paciente por
# hora (sem isso, repetir o formulário enchia o WhatsApp dele e somava
# chutes). A página responde IGUAL para qualquer telefone (LGPD: ninguém
# descobre pelo formulário se um número é paciente da clínica). Robô de coluna: card de origem 'formulario' cujo
# paciente nunca escreveu não recebe nada que fale com ele (anonymous_card?).
module Crm::FormVerification # rubocop:disable Metrics/ModuleLength
  module_function

  CODE_TTL = 10.minutes
  MAX_TRIES = 5
  CODE_DIGITS = 6
  REPLY_WINDOW = 24.hours
  AUTO_LABEL = 'formulario_codigo'.freeze
  PENDING_KEY = 'cevico_form_pending'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  # no máximo 3 códigos por paciente por hora (soma todas as respostas dele)
  CODES_PER_HOUR = 3
  # tarefas "lead do formulário sem conversa" por formulário por dia
  PENDING_TASKS_PER_DAY = ENV.fetch('CEVICO_FORM_DAILY_PENDING_TASKS', '20').to_i

  def code_key(response)
    "cevico:form_code:#{response.id}"
  end

  def tries_key(response)
    "cevico:form_code_tries:#{response.id}"
  end

  def cap_key(form, date = today)
    "cevico:form_cap:#{form.id}:#{date.iso8601}"
  end

  def contact_codes_key(contact)
    "cevico:form_code_contact:#{contact.id}"
  end

  def pending_tasks_key(form, date = today)
    "cevico:form_pending_tasks:#{form.id}:#{date.iso8601}"
  end

  def today
    Time.current.in_time_zone(TZ).to_date
  end

  # ── (2) código para cadastro existente ───────────────────────────────────
  # Devolve { status: 'sent' } quando o código saiu pela conversa do paciente,
  # ou { status: 'none', reason: ... } quando não dá para enviar (a resposta
  # então fica "não confirmada" para a equipe conferir). Isto é só para o
  # servidor e os testes: a página pública recebe SEMPRE a mesma resposta.
  def start!(response)
    reason = cannot_send_reason(response)
    return none(reason) if reason

    conversation = reply_window_conversation(response.contact)
    return none('sem_janela') if conversation.nil?
    return none('limite_codigos') unless code_slot?(response.contact)

    code = new_code
    return none('ja_enviado') unless Redis::Alfred.set(code_key(response), code, nx: true, ex: CODE_TTL.to_i)

    deliver_or_release!(response, conversation, code)
    { status: 'sent' }
  rescue StandardError => e
    Rails.logger.error "[Crm::FormVerification] código não enviado (resposta #{response.id}): #{e.class}: #{e.message}"
    none('erro')
  end

  def none(reason)
    { status: 'none', reason: reason }
  end

  # por que NÃO dá para mandar código (nil = pode): sem paciente, resposta que
  # não espera código (link assinado / paciente novo) ou paciente de parceiro
  def cannot_send_reason(response)
    contact = response.contact
    return 'sem_paciente' if contact.nil?
    return 'sem_marca' unless response.awaiting_code?
    return nil unless Crm::PartnerGuard.partner_contact?(contact)

    Crm::PartnerGuard.block!('código do formulário público', contact: contact)
    'parceiro'
  end

  # conta o código no paciente (vale para todas as respostas dele): passou de
  # CODES_PER_HOUR na hora → não manda mais nada (a resposta fica "não
  # confirmada"). Redis fora do ar → não manda (o lado seguro).
  def code_slot?(contact)
    key = contact_codes_key(contact)
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 1.hour.to_i) if count == 1
    count <= CODES_PER_HOUR
  end

  def new_code
    format("%0#{CODE_DIGITS}d", SecureRandom.random_number(10**CODE_DIGITS))
  end

  # a mensagem não saiu → libera o Redis para tentar de novo
  def deliver_or_release!(response, conversation, code)
    deliver!(conversation, code)
  rescue StandardError
    Redis::Alfred.delete(code_key(response))
    raise
  end

  # a conversa em que o paciente FALOU com a clínica nas últimas 24 h, numa
  # caixa presa ao telefone (WhatsApp/SMS) e fora da cerca dos parceiros —
  # ali a mensagem simples sai sem modelo pago
  def reply_window_conversation(contact)
    account = contact.account
    contact.conversations.includes(:inbox, :contact_inbox)
           .order(Arel.sql('last_activity_at DESC NULLS LAST, created_at DESC'))
           .limit(20)
           .find do |conversation|
      Crm::SendTemplateService.phone_bound?(conversation.inbox) &&
        !Crm::PartnerGuard.partner_inbox?(account, conversation.inbox_id) &&
        patient_wrote_recently?(conversation) &&
        conversation.can_reply?
    end
  end

  def patient_wrote_recently?(conversation)
    last = conversation.messages.where(account_id: conversation.account_id).incoming.last
    last.present? && last.created_at > REPLY_WINDOW.ago
  end

  def deliver!(conversation, code)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :outgoing, content: message_text(code),
      # 'cevico_auto': mensagem de robô — as automações de "mensagem enviada" ignoram
      additional_attributes: { 'cevico_auto' => AUTO_LABEL }
    )
  end

  def message_text(code)
    "CEVICO: seu código para confirmar as respostas do formulário é #{code}. " \
      'Digite o código na página do formulário (não precisa responder aqui). ' \
      'Ele vale 10 minutos. Se não foi você que preencheu, ignore esta mensagem.'
  end

  # ── confere o código digitado na página ──────────────────────────────────
  # { ok: true } | { ok: false, error: 'wrong' | 'locked', remaining: n }
  # 🔐 LGPD: resposta sem código (telefone desconhecido, sem conversa, código
  # vencido, já confirmada) responde IGUAL a código errado — senão a página
  # contaria quem é paciente com conversa recente na clínica.
  def verify!(response, code)
    remaining = MAX_TRIES - count_try!(response)
    stored = response.awaiting_code? ? Redis::Alfred.get(code_key(response)) : nil
    if remaining.negative? || stored.blank? || !code_matches?(code, stored)
      Redis::Alfred.delete(code_key(response)) if remaining <= 0 # última tentativa errada: o código morre
      return { ok: false, error: remaining <= 0 ? 'locked' : 'wrong', remaining: [remaining, 0].max }
    end

    confirm!(response)
    { ok: true }
  end

  # conta a tentativa (a contagem some junto com o código, em 10 min)
  def count_try!(response)
    tries = Redis::Alfred.incr(tries_key(response))
    Redis::Alfred.expire(tries_key(response), CODE_TTL.to_i) if tries == 1
    tries
  end

  # só dígitos, no tamanho certo, comparados em tempo constante
  def code_matches?(typed, stored)
    digits = typed.to_s.gsub(/\D/, '')
    digits.length == CODE_DIGITS && ActiveSupport::SecurityUtils.secure_compare(digits, stored.to_s)
  end

  def confirm!(response)
    Redis::Alfred.delete(code_key(response))
    Redis::Alfred.delete(tries_key(response))
    response.confirm_by_code!
    promote!(response.contact, response.form)
  end

  # paciente confirmou que é ele → se ainda não tem card no funil, ganha o
  # card em "Agendamento de Consulta" (decisão 01/09: o link só vai para quem
  # decidiu agendar). Card que já existe não anda de coluna.
  def promote!(contact, form)
    return nil if contact.nil?

    stage = booking_stage(form.account_id)
    return nil if stage.nil?

    Crm::Stamp.with(via: 'paciente') do
      Crm::Contact.find_or_create_by!(contact_id: contact.id, pipeline_id: stage.pipeline_id) do |card|
        card.stage_id = stage.id
        card.origin = 'formulario'
      end
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil # corrida com outro caminho que criou o card — já existe
  end

  def booking_stage(account_id)
    scope = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account_id })
    scope.where('crm_stages.name ILIKE ?', '%agendamento%consulta%').order(:position).first ||
      scope.where('crm_stages.name ILIKE ?', '%agendamento%').order(:position).first ||
      scope.order(:position).first
  end

  # ── (3) telefone desconhecido ────────────────────────────────────────────
  # marca no paciente novo: veio do formulário público e ninguém provou o
  # telefone (sem card até ele escrever no WhatsApp)
  def mark_pending!(contact, form:, response:, informed_name: nil)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      attrs.merge(PENDING_KEY => { 'form_id' => form.id, 'response_id' => response.id,
                                   'informed_name' => informed_name.to_s.strip[0, 120].presence,
                                   'at' => Time.current.iso8601 }.compact)
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::FormVerification] marca pendente (paciente #{contact&.id}): #{e.message}"
  end

  # a equipe precisa ENXERGAR o lead novo (ele não tem card): tarefa leve
  # "ligar e confirmar" para quem cuida (Crm::HandoffTask — uma por paciente).
  # No máximo PENDING_TASKS_PER_DAY por formulário por dia, para um ataque
  # não encher o Meu Painel (o teto de cadastros já avisa o admin).
  def open_pending_task!(contact, form:)
    return nil if contact.nil? || !pending_task_slot?(form)

    Crm::HandoffTask.open!(
      account: form.account, contact: contact, conversation: nil, agent_key: 'Formulário público',
      motivo: 'Lead do formulário sem conversa — ligar e confirmar',
      detalhes: "Alguém preencheu o formulário «#{form.name}» pelo link aberto com este WhatsApp, que ainda não " \
                'conversa com a clínica. O número NÃO foi confirmado: antes de agendar, confirme com a pessoa ' \
                '(ligação ou WhatsApp). As respostas estão no hub dos Formulários como "não confirmada".'
    )
  rescue StandardError => e
    Rails.logger.warn "[Crm::FormVerification] tarefa do lead do formulário (paciente #{contact&.id}): #{e.message}"
    nil
  end

  def pending_task_slot?(form)
    key = pending_tasks_key(form)
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 1.day.to_i) if count == 1
    count <= PENDING_TASKS_PER_DAY
  rescue StandardError
    true
  end

  # o envio contou no teto mas não criou ninguém (caiu num cadastro que já
  # existia ou deu erro): devolve a vaga do dia
  def release_new_contact_slot!(form)
    Redis::Alfred.with { |conn| conn.decr(cap_key(form)) }
  rescue StandardError
    nil
  end

  # teto diário GLOBAL de cadastros novos por formulário (conta antes de criar;
  # Redis fora do ar não trava a página — o freio por IP do rack_attack continua)
  def new_contact_allowed?(form)
    key = cap_key(form)
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 1.day.to_i) if count == 1
    cap = Crm::Form::DAILY_NEW_CONTACTS
    return true if count <= cap

    alert_cap!(form, cap) if count == cap + 1 # só a primeira vez que estoura no dia
    false
  rescue StandardError => e
    Rails.logger.error "[Crm::FormVerification] teto diário (formulário #{form.id}): #{e.class}: #{e.message}"
    true
  end

  # tarefa 🔴 para o administrador: alguém está criando cadastros em massa
  # pelo link público (ou o teto ficou baixo para o uso real)
  def alert_cap!(form, cap)
    account = form.account
    admin = account.administrators.order(:id).first || account.users.order(:id).first
    Rails.logger.warn "[Crm::FormVerification] formulário #{form.id} (#{form.name}) passou de #{cap} cadastros novos hoje"
    return if admin.nil?

    account.tasks.create!(
      title: "🔴 Formulário «#{form.name}»: teto diário de cadastros novos atingido (#{cap})",
      description: "#{TZ.now.strftime('%d/%m %H:%M')} · O link limpo #{form.public_short_link} já criou #{cap} pacientes novos hoje. " \
                   'Os envios seguintes de telefones desconhecidos foram recusados até amanhã. ' \
                   'Vale conferir se é uso real (aí o teto sobe pela variável CEVICO_FORM_DAILY_NEW_CONTACTS) ' \
                   'ou alguém enchendo o formulário de propósito.',
      task_type: Crm::HandoffTask::TASK_TYPE, priority: :urgent, status: :todo, due_at: TZ.now,
      creator: admin, assignee: admin
    )
  rescue StandardError => e
    Rails.logger.warn "[Crm::FormVerification] tarefa do teto não criada: #{e.message}"
  end

  # ── robôs de coluna ──────────────────────────────────────────────────────
  # card que NASCEU do formulário público e cujo paciente nunca escreveu para
  # a clínica: ninguém provou que o número é dele — nada que fale com ele sai
  def anonymous_card?(contact, pipeline)
    return false if contact.nil? || pipeline.nil?
    return false unless Crm::Contact.exists?(contact_id: contact.id, pipeline_id: pipeline.id, origin: 'formulario')

    !Message.incoming.exists?(account_id: contact.account_id, conversation_id: contact.conversations.select(:id))
  end
end
