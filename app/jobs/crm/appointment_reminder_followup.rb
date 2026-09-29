# 🔁 REFORÇO DO LEMBRETE DE CONSULTA (item 288, 29/09 — pedido do Guilherme:
# "enviamos a confirmação e ele passa 6 horas e não responde; precisamos
# poder enviar outra mensagem de lembrete, ainda que seja mensagem modelo").
#
# Cada lembrete (dN) pode ter um REFORÇO — desligado por padrão:
#   rcfg['followup'] = { enabled, hours (6), max (1 ou 2), template_params,
#                        message_preview, partner: { template_params, message_preview } }
#
# Quem recebe: consulta que JÁ recebeu o lembrete dN ao vivo, ainda vai
# acontecer, e o paciente NÃO respondeu nada desde o lembrete, nem confirmou,
# recusou, cancelou ou remarcou. O 2º reforço conta as horas a partir do 1º.
#
# Só sai entre 07h e 20h (São Paulo): a rodada é a cada 15 min, então o que
# venceria de madrugada sai na primeira rodada depois das 07h. Nunca depois
# do horário da consulta.
#
# NUNCA DUAS VEZES: antes de enviar, a marca "dN_f1"/"dN_f2" é gravada no
# contato DENTRO da trava de linha (Cevico::AttributeMerge) — quem chegar em
# segundo lugar encontra a marca e desiste. Se o envio nem chegou a sair
# (sem caixa/contato), a marca é devolvida; se deu erro no meio, a marca FICA
# (melhor faltar um reforço do que repetir mensagem para o paciente).
#
# PACIENTES DO OFTALMOFÁCIL: a mesma regra do lembrete (item 259) — só com o
# bloco deles ligado, pela caixa deles, com o modelo de reforço DELES. Sem IA.
module Crm::AppointmentReminderFollowup # rubocop:disable Metrics/ModuleLength
  WINDOW_HOURS = (7...20)
  DEFAULT_HOURS = 6
  HOURS_RANGE = (1..48)
  MAX_FOLLOWUPS = 2
  LOOKAHEAD = 8.days
  # reforço "vencido" há mais de um dia não sai (ex.: o admin ligou o reforço
  # hoje e existem lembretes antigos sem resposta — não vira rajada)
  STALE_AFTER = 24.hours
  STATE_LIST = 'followups'.freeze
  LIST_CAP = 60

  def self.mark_key(regua, number)
    "#{regua}_f#{number}"
  end

  def self.due_key(regua)
    "#{regua}_due"
  end

  def self.hours_of(rcfg)
    value = rcfg.dig('followup', 'hours').to_i
    value.positive? ? value.clamp(HOURS_RANGE.min, HOURS_RANGE.max) : DEFAULT_HOURS
  end

  def self.max_of(rcfg)
    value = rcfg.dig('followup', 'max').to_i
    value.positive? ? value.clamp(1, MAX_FOLLOWUPS) : 1
  end

  # reforço só existe para lembrete LIGADO e AO VIVO (sombra não manda nada)
  def self.enabled?(rcfg)
    rcfg['enabled'] == true && rcfg['mode'] != 'shadow' && rcfg.dig('followup', 'enabled') == true
  end

  private

  def run_followups(account, cfg, now_sp) # rubocop:disable Metrics/CyclomaticComplexity
    return unless WINDOW_HOURS.cover?(now_sp.hour)

    (self.class::REGUAS & cfg.keys).each do |regua|
      rcfg = cfg[regua] || {}
      next unless Crm::AppointmentReminderFollowup.enabled?(rcfg)

      sent = followup_tasks(account, now_sp).filter_map { |task| followup_for(account, regua, rcfg, task, now_sp) }
      record_followups(account, regua, sent) if sent.any?
    rescue StandardError => e
      Rails.logger.error "[CEVICO reforço] conta #{account.id} #{regua}: #{e.message}"
    end
  end

  # consultas que ainda vão acontecer e seguem sem resposta do paciente
  def followup_tasks(account, now_sp)
    account.tasks.where(task_type: 'consulta', canceled_at: nil, archived_at: nil, confirmed_at: nil, declined_at: nil)
           .where(attendance: [nil, ''])
           .where(due_at: now_sp..(now_sp + LOOKAHEAD))
           .where.not(contact_id: nil)
           .includes(:contact)
  end

  # devolve a linha do histórico quando o reforço saiu; nil quando não era o caso
  def followup_for(account, regua, rcfg, task, now_sp) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    contact = task.contact
    entry = (contact.additional_attributes || {}).dig('cevico_appt_reminders', task.id.to_s) || {}
    number = followup_number(entry, regua, rcfg, now_sp)
    return nil if number.nil?
    return nil if followup_rescheduled?(regua, rcfg, entry, task)
    return nil if skip_reason(rcfg, regua, task, contact)
    return nil if followup_replied?(contact, followup_time(entry[regua]))

    partner = partner_patient?(task, contact)
    inbox = account.inboxes.find_by(id: partner ? rcfg.dig('partner', 'inbox_id') : rcfg['inbox_id'])
    template = followup_template(rcfg, partner)
    return nil if inbox.nil? || template.nil?
    return nil unless claim_followup!(contact, task, regua, number, now_sp)

    deliver_followup(account, inbox, rcfg, regua, task, template, number, now_sp, partner: partner)
  rescue StandardError => e
    Rails.logger.error "[CEVICO reforço] task #{task.id}: #{e.message}"
    nil
  end

  def deliver_followup(account, inbox, rcfg, regua, task, template, number, now_sp, partner:) # rubocop:disable Metrics/ParameterLists
    contact = task.contact
    source = self.class::TemplateSource.new(account, inbox, nil, personalized_params(template['template_params'], task, rcfg),
                                            template['message_preview'].presence,
                                            "Reforço #{number} do lembrete de consulta (#{regua.upcase})")
    conversation = Crm::SendTemplateService.new(source: source, contact: contact).perform
    if conversation.nil? # nada foi criado: devolve a marca para tentar de novo
      release_followup!(contact, task, regua, number)
      return nil
    end

    entry_for(task, contact, template: template.dig('template_params', 'name'), partner: partner)
      .merge('number' => number, 'at' => now_sp.iso8601)
  end

  # qual reforço é o da vez (1 ou 2) — nil quando não é hora de nenhum
  def followup_number(entry, regua, rcfg, now_sp) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if entry[regua].blank? || entry['confirmed'].present? || entry['declined'].present?

    done = (1..MAX_FOLLOWUPS).take_while { |n| entry[Crm::AppointmentReminderFollowup.mark_key(regua, n)].present? }.size
    number = done + 1
    return nil if number > Crm::AppointmentReminderFollowup.max_of(rcfg)

    last_at = followup_time(done.zero? ? entry[regua] : entry[Crm::AppointmentReminderFollowup.mark_key(regua, done)])
    return nil if last_at.nil?

    due_at = last_at + Crm::AppointmentReminderFollowup.hours_of(rcfg).hours
    due_at.between?(now_sp - STALE_AFTER, now_sp) ? number : nil
  end

  def followup_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  # a consulta mudou de dia/hora depois do lembrete → não é mais "a mesma"
  def followup_rescheduled?(regua, rcfg, entry, task)
    due = followup_time(entry[Crm::AppointmentReminderFollowup.due_key(regua)])
    return due.to_i != task.due_at.to_i if due

    # lembrete enviado antes do item 288 (sem a hora guardada): confere o dia
    sent_at = followup_time(entry[regua])&.in_time_zone(self.class::TZ)
    sent_at.nil? || self.class.target_dates(regua, rcfg, sent_at).exclude?(task.due_at.in_time_zone(self.class::TZ).to_date)
  end

  # o paciente escreveu QUALQUER coisa depois do lembrete?
  def followup_replied?(contact, since)
    return true if since.nil?

    Message.joins(:conversation).where(conversations: { contact_id: contact.id })
           .where(message_type: :incoming).exists?(['messages.created_at > ?', since])
  end

  def followup_template(rcfg, partner)
    base = partner ? rcfg.dig('followup', 'partner') : rcfg['followup']
    return nil if base.blank? || base['template_params'].blank?

    { 'template_params' => base['template_params'], 'message_preview' => base['message_preview'] }
  end

  # grava a marca ANTES de enviar, dentro da trava; false = outro já pegou
  # (ou o paciente confirmou/recusou nesse meio-tempo)
  def claim_followup!(contact, task, regua, number, now_sp) # rubocop:disable Metrics/CyclomaticComplexity
    key = Crm::AppointmentReminderFollowup.mark_key(regua, number)
    claimed = false
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      marks = attrs['cevico_appt_reminders'] || {}
      entry = marks[task.id.to_s] || {}
      next attrs if entry[regua].blank? || entry[key].present? || entry['confirmed'].present? || entry['declined'].present?

      claimed = true
      attrs.merge('cevico_appt_reminders' => marks.merge(task.id.to_s => entry.merge(key => now_sp.iso8601)))
    end
    claimed
  end

  def release_followup!(contact, task, regua, number)
    key = Crm::AppointmentReminderFollowup.mark_key(regua, number)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      marks = attrs['cevico_appt_reminders'] || {}
      entry = (marks[task.id.to_s] || {}).except(key)
      attrs.merge('cevico_appt_reminders' => marks.merge(task.id.to_s => entry))
    end
  end

  # histórico dos reforços enviados (mais novos primeiro), ao lado da última rodada
  def record_followups(account, regua, sent)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    settings.with_lock do
      agenda = settings.agenda_config || {}
      state = agenda[self.class::STATE_KEY] || {}
      lists = state[STATE_LIST] || {}
      lists[regua] = (sent.reverse + Array(lists[regua])).first(LIST_CAP)
      settings.update!(agenda_config: agenda.merge(self.class::STATE_KEY => state.merge(STATE_LIST => lists)))
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO reforço] registro: #{e.message}"
  end
end
