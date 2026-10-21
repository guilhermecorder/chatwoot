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

  # item 310: a caixa pela qual o lembrete saiu (o reforço usa a mesma)
  def self.inbox_key(regua)
    "#{regua}_inbox"
  end

  # 🚫 #45 (revisão da Rodada 3): id da mensagem do reforço, guardado na marca
  # da consulta — a rodada seguinte confere se a Meta recusou
  def self.message_key(regua, number)
    "#{mark_key(regua, number)}_message_id"
  end

  # nota "a Meta recusou o reforço" desta régua: nenhum outro reforço dela sai
  # sozinho (a causa costuma ser a mesma); consulta remarcada = ciclo novo
  def self.refused_key(regua)
    "#{regua}_f_refused"
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
    # 🚫 #45: reforço que a Meta recusou deixa de contar (fora da janela também — a recusa pode chegar de noite)
    reconcile_refused_followups(account, self.class::REGUAS & cfg.keys, now_sp)
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
    # a régua seguinte (mais perto da consulta) já saiu: o reforço desta perde o sentido (varredura 03/10)
    return nil if closer_reminder_sent?(entry, regua)
    return nil if skip_reason(rcfg, regua, task, contact)
    return nil if followup_replied?(contact, followup_time(entry[regua]))

    partner = partner_patient?(task, contact)
    # item 310: o reforço sai pela mesma caixa em que o lembrete saiu
    sent_by = entry[Crm::AppointmentReminderFollowup.inbox_key(regua)]
    inbox = account.inboxes.find_by(id: partner ? rcfg.dig('partner', 'inbox_id') : (sent_by || rcfg['inbox_id']))
    # 🎯 item 327: o reforço também tem modelo personalizado por médico / tipo de atendimento
    inbox, template = partner ? [inbox, followup_template(rcfg, true)] : followup_route(account, rcfg, inbox, task)
    return nil if inbox.nil? || template.nil?
    return nil unless claim_followup!(contact, task, regua, number, now_sp)

    deliver_followup(account, inbox, rcfg, regua, task, template, number, now_sp, partner: partner)
  rescue StandardError => e
    Rails.logger.error "[CEVICO reforço] task #{task.id}: #{e.message}"
    nil
  end

  def deliver_followup(account, inbox, rcfg, regua, task, template, number, now_sp, partner:) # rubocop:disable Metrics/ParameterLists
    contact = task.contact
    params = personalized_params(template['template_params'], task, rcfg, template['message_preview'])
    source = self.class::TemplateSource.new(account, inbox, nil, params, template['message_preview'].presence,
                                            "Reforço #{number} do lembrete de consulta (#{regua.upcase})")
    sender = Crm::SendTemplateService.new(source: source, contact: contact)
    conversation = sender.perform
    if conversation.nil? # nada foi criado: devolve a marca para tentar de novo
      release_followup!(contact, task, regua, number)
      return nil
    end

    # a mensagem gravada fica na marca: a rodada seguinte confere se a Meta recusou (#45)
    remember_reminder_message!(contact, task, Crm::AppointmentReminderFollowup.message_key(regua, number), sender.message&.id)
    entry_for(task, contact, template: template.dig('template_params', 'name'), partner: partner, inbox: inbox, model: template['model'],
                             message_id: sender.message&.id)
      .merge('number' => number, 'at' => now_sp.iso8601)
  end

  # qual reforço é o da vez (1 ou 2) — nil quando não é hora de nenhum
  def followup_number(entry, regua, rcfg, now_sp) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if entry[regua].blank? || entry['confirmed'].present? || entry['declined'].present?
    return nil if entry[Crm::AppointmentReminderFollowup.refused_key(regua)].present? # #45: a Meta recusou um reforço desta régua

    done = (1..MAX_FOLLOWUPS).take_while { |n| entry[Crm::AppointmentReminderFollowup.mark_key(regua, n)].present? }.size
    number = done + 1
    return nil if number > Crm::AppointmentReminderFollowup.max_of(rcfg)

    last_at = followup_time(done.zero? ? entry[regua] : entry[Crm::AppointmentReminderFollowup.mark_key(regua, done)])
    return nil if last_at.nil?

    due_at = last_at + Crm::AppointmentReminderFollowup.hours_of(rcfg).hours
    due_at.between?(now_sp - STALE_AFTER, now_sp) ? number : nil
  end

  def closer_reminder_sent?(entry, regua)
    days = self.class.days_of(regua)
    self.class::REGUAS.any? { |r| self.class.days_of(r) < days && entry[r].present? }
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

  # item 314: reforço pela outra caixa usa o modelo do reforço escolhido
  # para ela; sem ele, o reforço sai pela caixa padrão com o modelo padrão.
  # 🎯 item 327: em cada caixa, o modelo personalizado (médico / tipo de
  # atendimento) do reforço vem antes do padrão dela.
  def followup_route(account, rcfg, inbox, task)
    return [nil, nil] if inbox.nil?

    unless inbox.id == rcfg['inbox_id'].to_i
      own = Crm::ReminderModels.followup(inbox_config(rcfg, inbox), task)
      return [inbox, own] if own
    end
    base = Crm::ReminderModels.followup(rcfg, task)
    [base && account.inboxes.find_by(id: rcfg['inbox_id']), base]
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
      entry = (marks[task.id.to_s] || {}).except(key, Crm::AppointmentReminderFollowup.message_key(regua, number))
      attrs.merge('cevico_appt_reminders' => marks.merge(task.id.to_s => entry))
    end
  end

  # ── a Meta recusou o reforço (#45, revisão da Rodada 3) ───────────────
  # Mesmo desenho da conferência do lembrete: lê a marca dN_fK_message_id das
  # consultas de hoje em diante; a recusada devolve a marca (o 2º reforço não
  # conta horas de uma mensagem que nunca chegou), ganha a nota que barra
  # novos reforços desta régua, aparece na lista "Reforços enviados" como
  # recusada e a responsável é avisada (tarefa por paciente ou resumo).
  def reconcile_refused_followups(account, reguas, now_sp)
    hits = refused_followup_hits(account, reguas, now_sp)
    return if hits.empty?

    hits.each { |hit| refuse_followup!(hit[:contact], hit[:task], hit[:regua], hit[:number], hit[:error]) }
    record_refused_followups(account, hits)
    notify_refused_all(account, hits)
  rescue StandardError => e
    Rails.logger.warn "[CEVICO reforço] conferência das recusas: #{e.message}"
  end

  def refused_followup_hits(account, reguas, now_sp)
    return [] if reguas.empty?

    found = upcoming_marks(account, now_sp).flat_map do |task, contact, entry|
      reguas.product((1..MAX_FOLLOWUPS).to_a).filter_map do |regua, number|
        id = entry[Crm::AppointmentReminderFollowup.message_key(regua, number)]
        { task: task, contact: contact, regua: regua, number: number, message_id: id } if id.present?
      end
    end
    with_meta_errors(found)
  end

  # devolve a marca do reforço recusado e deixa a nota na consulta
  def refuse_followup!(contact, task, regua, number, error)
    note = { 'number' => number, 'error' => error.to_s.truncate(160), 'at' => Time.current.iso8601 }
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      marks = attrs['cevico_appt_reminders'] || {}
      entry = (marks[task.id.to_s] || {})
              .except(Crm::AppointmentReminderFollowup.mark_key(regua, number), Crm::AppointmentReminderFollowup.message_key(regua, number))
              .merge(Crm::AppointmentReminderFollowup.refused_key(regua) => note)
      attrs.merge('cevico_appt_reminders' => marks.merge(task.id.to_s => entry))
    end
  end

  # na lista "Reforços enviados", a linha do reforço recusado ganha o erro da Meta
  def record_refused_followups(account, hits)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    texts = hits.to_h { |h| [[h[:regua], h[:task].id, h[:number]], "a Meta recusou: #{h[:error].to_s.truncate(80)}"] }
    # Rodada 4 (achado #383): sob a trava da linha, só o estado deste robô muda
    Cevico::SettingMerge.merge_key!(settings, :agenda_config, self.class::STATE_KEY) do |state|
      state.merge(STATE_LIST => refused_lines(state[STATE_LIST] || {}, texts))
    end
  end

  def refused_lines(lists, texts)
    lists.to_h do |regua, list|
      [regua, Array(list).map { |e| (text = texts[[regua, e['task_id'], e['number']]]) ? e.merge('refused' => text) : e }]
    end
  end

  # histórico dos reforços enviados (mais novos primeiro), ao lado da última rodada
  def record_followups(account, regua, sent)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    # Rodada 4 (achado #383): sob a trava da linha, só o estado deste robô muda
    Cevico::SettingMerge.merge_key!(settings, :agenda_config, self.class::STATE_KEY) do |state|
      lists = state[STATE_LIST] || {}
      state.merge(STATE_LIST => lists.merge(regua => (sent.reverse + Array(lists[regua])).first(LIST_CAP)))
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO reforço] registro: #{e.message}"
  end
end
