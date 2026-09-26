# 📅 LEMBRETES PELO DIA DA CONSULTA (item 156, pacote COMPARECIMENTO):
#   D-2 = dois dias antes, a CONFIRMAÇÃO COMPLETA da consulta (item 250, 26/09:
#         substitui os fluxos "CONFIRMACAO CONSULTA PAULISTA/TATUAPÉ" do N8N,
#         que liam o Google Agenda — agora a fonte é a NOSSA Agenda)
#   D-1 = véspera, pedindo confirmação por resposta ("responde SIM")
#   D-0 = no dia (ex.: 07h), lembrando que a consulta é hoje
#
# Cron a cada 15 min; cada régua só age na HORA configurada da conta
# (Automações → Robôs → "Lembretes do dia da consulta") e cada consulta
# recebe NO MÁXIMO 1 envio por régua — a marca fica no contato
# (additional_attributes.cevico_appt_reminders[task_id]), então repetir a
# rodada dentro da mesma hora não duplica nada.
#
# O envio é MENSAGEM MODELO (Crm::SendTemplateService, o mesmo das
# Campanhas) — chega mesmo com a janela de 24h fechada. Nos valores das
# variáveis, {{hora}} vira o horário da consulta, {{unidade}} vira a casa
# (Av. Paulista/Tatuapé), {{data}} a data dd/mm/aaaa, {{nome}} o nome do
# paciente e {{valor}} o valor da avaliação; {{contact.name}} segue com o
# Liquid do serviço.
#
# A régua D-2 tem MODELO POR UNIDADE (a mensagem da Paulista tem endereço e
# estacionamento; a do Tatuapé, outro endereço), pode rodar em SOMBRA (só
# lista quem receberia, para comparar com o N8N antes de desligar o N8N) e,
# na sexta, adianta a de segunda (D-3) — como o N8N fazia.
#
# A CONFIRMAÇÃO da D-2/D-1 é lida pelo CrmListener (resposta "sim/confirmo"
# de quem tem lembrete enviado) — vira marca confirmed + nota na conversa.
# Quem já confirmou não recebe a D-2 nem a D-1 de novo.
#
# PACIENTES DO OFTALMOFÁCIL (26/09, pedido do Guilherme): a cerca dos parceiros
# (item 231) continua valendo — mas cada lembrete pode LIBERAR o envio para
# eles por UMA caixa escolhida (rcfg['partner'] = { enabled, inbox_id,
# template_params, message_preview }), com modelo próprio. Só mensagem modelo
# + leitura do "sim/não" por palavra; nenhuma IA fala com eles (a conversa
# segue travada pela cerca no CrmListener). Sem o bloco ligado, nada muda:
# paciente de parceiro é pulado como antes.
class Crm::AppointmentReminderSendJob < ApplicationJob
  queue_as :scheduled_jobs

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  # item 253 (26/09): QUANTOS lembretes quiser, de 0 a 7 dias antes — cada um
  # é uma chave dN em agenda_config.appointment_reminders (d2 = 2 dias antes,
  # d1 = véspera, d0 = no dia…). As chaves antigas d2/d1/d0 continuam valendo.
  REGUAS = (0..7).map { |n| "d#{n}" }.freeze
  MAX_MARK_ENTRIES = 60 # marcas antigas são podadas (consultas já passaram)
  DEFAULT_VALUE = '150,00'.freeze
  STATE_KEY = 'appointment_reminders_state'.freeze
  # interruptor geral do agente "Confirmação de consulta" (Agentes de IA)
  MASTER_KEY = 'appointment_confirmation'.freeze
  LIST_CAP = 80

  # fonte leve compartilhada (item 168 — antes cada job tinha a sua cópia)
  TemplateSource = Crm::TemplateSource

  # now: só os testes passam (congelar o relógio sem gem de viagem no tempo)
  def perform(now = nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    now_sp = now ? now.in_time_zone(TZ) : TZ.now
    CrmSetting.find_each do |settings|
      next if settings.agenda_config&.dig(MASTER_KEY, 'enabled') == false

      cfg = settings.agenda_config&.dig('appointment_reminders') || {}
      (REGUAS & cfg.keys).each do |regua|
        run_regua(settings.account, regua, cfg[regua] || {}, now_sp)
      rescue StandardError => e
        Rails.logger.error "[CEVICO lembretes] conta #{settings.account_id} #{regua}: #{e.message}"
      end
    end
  end

  def self.days_of(regua)
    regua.to_s.delete_prefix('d').to_i
  end

  def self.default_hour(regua)
    days_of(regua).zero? ? 7 : 10
  end

  # dias-alvo da régua: dN = hoje + N. Com weekend_bridge (lembretes de 1 ou 2
  # dias antes), na SEXTA também vai o da segunda — o envio normal cairia no
  # fim de semana (como o N8N fazia); sábado/domingo o robô segue rodando e a
  # marca por consulta impede a repetição
  def self.target_dates(regua, rcfg, now_sp)
    today = now_sp.to_date
    days = days_of(regua)
    dates = [today + days]
    dates << (today + 3) if rcfg['weekend_bridge'] == true && today.friday? && days.between?(1, 2)
    dates
  end

  private

  def run_regua(account, regua, rcfg, now_sp) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return unless rcfg['enabled'] == true
    return unless now_sp.hour == (rcfg['hour'] || self.class.default_hour(regua)).to_i

    # sombra = só lista quem receberia; regra antiga sem 'mode' segue ao vivo
    shadow = rcfg['mode'] == 'shadow'
    inbox = account.inboxes.find_by(id: rcfg['inbox_id'])
    return if inbox.nil? && !shadow
    return if rcfg['template_params'].blank? && templates_by_unit(rcfg).none? && !shadow

    run = { 'sent' => [], 'skipped' => [] }
    self.class.target_dates(regua, rcfg, now_sp).each do |date|
      day_start = TZ.local(date.year, date.month, date.day)
      scope = account.tasks.where(task_type: 'consulta', canceled_at: nil, archived_at: nil)
                     .where(due_at: day_start..day_start.end_of_day)
                     .where(attendance: [nil, ''])
                     .where.not(contact_id: nil)
      scope = scope.where(confirmed_at: nil) if self.class.days_of(regua).positive? # quem já confirmou não recebe de novo
      scope.includes(:contact).find_each { |task| send_for(account, inbox, rcfg, regua, task, run, shadow: shadow) }
    end
    record_run(account, regua, run, now_sp, shadow: shadow)
  end

  def send_for(account, inbox, rcfg, regua, task, run, shadow: false) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
    contact = task.contact
    blocked = skip_reason(rcfg, regua, task, contact)
    return skip(run, task, blocked) if blocked

    marks = (contact.additional_attributes || {}).dig('cevico_appt_reminders', task.id.to_s) || {}
    return if marks[regua].present?

    # paciente de parceiro (já liberado no skip_reason) sai pela caixa e modelo do bloco Oftalmofácil
    partner = partner_patient?(task, contact)
    if partner
      inbox = account.inboxes.find_by(id: rcfg.dig('partner', 'inbox_id'))
      return skip(run, task, 'Oftalmofácil: caixa não encontrada') if inbox.nil? && !shadow
    end
    template = partner ? partner_template(rcfg) : template_for(rcfg, regua, task)
    return skip(run, task, partner ? 'Oftalmofácil: sem modelo' : "sem modelo para #{unit_label(task)}") if template.nil? && !shadow

    if shadow
      run['sent'] << entry_for(task, contact, template: template&.dig('template_params', 'name'), partner: partner)
      return
    end

    source = TemplateSource.new(account, inbox, nil,
                                personalized_params(template['template_params'], task, rcfg),
                                template['message_preview'].presence,
                                "Lembrete de consulta (#{regua.upcase})")
    conversation = Crm::SendTemplateService.new(source: source, contact: contact).perform
    return skip(run, task, 'envio não saiu (contato/caixa)') if conversation.nil?

    mark_sent(contact, task, regua)
    run['sent'] << entry_for(task, contact, template: template.dig('template_params', 'name'), partner: partner)
  rescue StandardError => e
    Rails.logger.error "[CEVICO lembretes] task #{task.id}: #{e.message}"
    skip(run, task, "erro: #{e.message.truncate(60)}")
  end

  # por que esta consulta NÃO recebe a régua (nil = pode receber)
  def skip_reason(rcfg, regua, task, contact) # rubocop:disable Metrics/CyclomaticComplexity
    return 'sem telefone' if contact.nil? || contact.phone_number.blank?

    # 🚧 item 231 (cerca dos parceiros): consulta/exame de parceiro do hub só recebe
    # o lembrete quando o bloco "Pacientes do Oftalmofácil" deste lembrete está ligado
    if partner_patient?(task, contact) && !partner_enabled?(rcfg)
      Crm::PartnerGuard.block!("lembrete #{regua} (agendamento #{task.id})", contact: contact)
      return 'paciente de parceiro (cerca)'
    end
    allowed = Array(rcfg['modalities']).compact_blank
    return nil if allowed.empty? || task.modality.blank? # sem filtro = todas as modalidades

    allowed.include?(task.modality) ? nil : "modalidade #{task.modality}"
  end

  def partner_patient?(task, contact)
    Crm::PartnerGuard.partner_task?(task) || Crm::PartnerGuard.partner_contact?(contact)
  end

  def partner_enabled?(rcfg)
    rcfg.dig('partner', 'enabled') == true && rcfg.dig('partner', 'inbox_id').to_i.positive?
  end

  def partner_template(rcfg)
    tp = rcfg.dig('partner', 'template_params')
    return nil if tp.blank?

    { 'template_params' => tp, 'message_preview' => rcfg.dig('partner', 'message_preview') }
  end

  # ── modelo certo para a consulta ──────────────────────────────────────
  # modelo da UNIDADE da consulta (units.paulista / units.tatuape), senão o
  # geral do lembrete. Devolve { 'template_params', 'message_preview' } ou nil.
  def template_for(rcfg, _regua, task)
    by_unit = templates_by_unit(rcfg)[task.unit.to_s]
    return by_unit if by_unit&.dig('template_params').present?
    return nil if rcfg['template_params'].blank?

    { 'template_params' => rcfg['template_params'], 'message_preview' => rcfg['message_preview'] }
  end

  def templates_by_unit(rcfg)
    (rcfg['units'] || {}).select { |_u, t| t.is_a?(Hash) && t['template_params'].present? }
  end

  # {{hora}}/{{unidade}}/{{data}}/{{nome}}/{{valor}} nos VALORES das variáveis viram o dado da consulta
  def personalized_params(template_params, task, rcfg = {})
    params = template_params.deep_dup
    at = task.due_at&.in_time_zone(TZ)
    subs = {
      '{{hora}}' => at&.strftime('%H:%M').to_s,
      '{{data}}' => at&.strftime('%d/%m/%Y').to_s,
      '{{unidade}}' => unit_label(task),
      '{{nome}}' => patient_name(task),
      '{{parceiro}}' => partner_name(task),
      '{{valor}}' => appointment_value(task, rcfg)
    }
    body = params.dig('processed_params', 'body')
    body&.transform_values! { |v| subs.reduce(v.to_s) { |text, (key, val)| text.gsub(key, val) } }
    params
  end

  # valor da avaliação: "Valor: 250,00" ou "R$ 250" na observação da consulta;
  # senão o padrão da régua (150,00) — igual ao N8N fazia com a descrição do evento
  VALUE_PATTERNS = [/valor\s*:\s*(?:R\$\s*)?([\d.]+(?:,\d{1,2})?)/i, /R\$\s*([\d.]+(?:,\d{1,2})?)/i].freeze

  def appointment_value(task, rcfg)
    text = task.description.to_s
    raw = VALUE_PATTERNS.lazy.filter_map { |re| text.match(re)&.[](1) }.first.to_s.strip
    return rcfg['default_value'].presence || DEFAULT_VALUE if raw.blank?

    raw.include?(',') ? raw : "#{raw},00"
  end

  def patient_name(task)
    task.title.to_s.sub(/\A(Consulta|Exame|Retorno|Pós-operatório|Teleconsulta):\s*/i, '').strip.presence ||
      task.contact&.name.to_s.presence || 'Paciente'
  end

  # nome do parceiro do hub (o sync grava em source_detail) — vazio para a CEVICO
  def partner_name(task)
    task.source_detail.to_s.presence || (task.contact&.additional_attributes || {})['parceiro'].to_s
  end

  def unit_label(task)
    Crm::AgendaSlots::UNIT_LABELS[task.unit.to_s] || task.unit.to_s
  end

  # ── registro da rodada: quem recebeu / receberia e quem foi pulado ──
  def entry_for(task, contact, template: nil, partner: false)
    at = task.due_at&.in_time_zone(TZ)
    { 'task_id' => task.id, 'name' => patient_name(task), 'phone_tail' => contact.phone_number.to_s.last(4),
      'when' => at&.strftime('%d/%m %H:%M'), 'unit' => unit_label(task), 'template' => template, 'contact_id' => contact.id,
      'partner' => (partner ? partner_name(task).presence || 'Oftalmofácil' : nil) }.compact
  end

  def skip(run, task, why)
    run['skipped'] << { 'task_id' => task.id, 'name' => patient_name(task), 'why' => why,
                        'when' => task.due_at&.in_time_zone(TZ)&.strftime('%d/%m %H:%M'), 'unit' => unit_label(task) }
    nil
  end

  def record_run(account, regua, run, now_sp, shadow:) # rubocop:disable Metrics/CyclomaticComplexity
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    settings.with_lock do
      agenda = settings.agenda_config || {}
      rcfg = agenda.dig('appointment_reminders', regua) || {}
      state = agenda[STATE_KEY] || {}
      state[regua] = {
        'last_run_at' => Time.current.iso8601, 'mode' => shadow ? 'shadow' : 'live',
        'dates' => self.class.target_dates(regua, rcfg, now_sp).map(&:iso8601),
        'sent' => run['sent'].first(LIST_CAP), 'skipped' => run['skipped'].first(LIST_CAP)
      }
      settings.update!(agenda_config: agenda.merge(STATE_KEY => state))
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO lembretes] registro da rodada: #{e.message}"
  end

  def mark_sent(contact, task, regua)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      marks = attrs['cevico_appt_reminders'] || {}
      entry = marks[task.id.to_s] || {}
      entry[regua] = Time.current.iso8601
      marks[task.id.to_s] = entry
      # poda: marcas de consultas antigas não servem pra mais nada
      marks = marks.sort_by { |_id, e| e.values.max.to_s }.last(MAX_MARK_ENTRIES).to_h if marks.size > MAX_MARK_ENTRIES
      attrs.merge('cevico_appt_reminders' => marks)
    end
  end
end
