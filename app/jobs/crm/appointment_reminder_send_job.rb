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
class Crm::AppointmentReminderSendJob < ApplicationJob # rubocop:disable Metrics/ClassLength
  include Crm::AppointmentReminderFollowup

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
      # da régua mais distante (d7) para o dia (d0): na sexta com ponte, a
      # confirmação completa sai antes da véspera (varredura 03/10)
      (REGUAS & cfg.keys).sort_by { |r| -self.class.days_of(r) }.each do |regua|
        run_regua(settings.account, regua, cfg[regua] || {}, now_sp)
      rescue StandardError => e
        Rails.logger.error "[CEVICO lembretes] conta #{settings.account_id} #{regua}: #{e.message}"
      end
      # 🔁 item 288: reforço para quem não respondeu ao lembrete (desligado por padrão)
      run_followups(settings.account, cfg, now_sp)
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

  # 🖐️ ENVIO MANUAL pelo card (item 320, 03/10; "a possibilidade de um envio
  # manual, como esses casos, seria ótimo eu fazer um reenvio"):
  #   sem task_id = o lembrete INTEIRO agora, fora da hora — mesmas regras, só
  #                 para quem ainda não recebeu (a marca por consulta impede repetir);
  #   com task_id = ESTE paciente: sai mesmo com a coluna/tipo fora do filtro e
  #                 mesmo que já tenha recebido (reenvio). Telefone e a cerca dos
  #                 parceiros continuam valendo. Só com o lembrete AO VIVO.
  # Devolve { ok:, sent:, skipped:, why: } ou { ok: false, error: }.
  def run_manual(account, regua, task_id: nil, now: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    now_sp = (now || Time.current).in_time_zone(TZ)
    agenda = CrmSetting.find_by(account: account)&.agenda_config || {}
    rcfg = agenda.dig('appointment_reminders', regua)
    return { ok: false, error: 'Lembrete não encontrado — salve o card antes.' } unless REGUAS.include?(regua) && rcfg.is_a?(Hash)
    return { ok: false, error: 'A Confirmação de consulta está desligada.' } if agenda.dig(MASTER_KEY, 'enabled') == false
    return { ok: false, error: 'Ligue este lembrete antes de enviar.' } unless rcfg['enabled'] == true
    return { ok: false, error: 'Em sombra o lembrete não envia — mude para Ao vivo.' } if task_id && rcfg['mode'] == 'shadow'

    run = run_regua(account, regua, rcfg, now_sp, manual: true, task_id: task_id)
    return { ok: false, error: 'Falta a caixa do WhatsApp ou o modelo deste lembrete.' } if run.nil?
    return { ok: false, error: 'Consulta não encontrada (cancelada ou já passou).' } if task_id && run.values.all?(&:empty?)

    { ok: true, sent: run['sent'].size, skipped: run['skipped'].size, why: run['skipped'].first&.dig('why') }
  end

  private

  # manual: true = pedido pelo card (não olha a hora); task_id = só este paciente (força)
  def run_regua(account, regua, rcfg, now_sp, manual: false, task_id: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists
    return unless rcfg['enabled'] == true

    hour = (rcfg['hour'] || self.class.default_hour(regua)).to_i
    # a hora configurada e a seguinte: rodada perdida (deploy, fila parada) não
    # vira dia perdido — a marca por consulta impede repetição (varredura 03/10)
    return unless manual || now_sp.hour.between?(hour, hour + 1)

    # sombra = só lista quem receberia; regra antiga sem 'mode' segue ao vivo
    shadow = rcfg['mode'] == 'shadow'
    inbox = account.inboxes.find_by(id: rcfg['inbox_id'])
    return if inbox.nil? && !shadow
    return if rcfg['template_params'].blank? && templates_by_unit(rcfg).none? && !shadow
    return run_one(account, inbox, rcfg, regua, task_id, now_sp) if task_id

    run = { 'sent' => [], 'skipped' => [] }
    self.class.target_dates(regua, rcfg, now_sp).each do |date|
      day_start = TZ.local(date.year, date.month, date.day)
      scope = account.tasks.where(task_type: 'consulta', canceled_at: nil, archived_at: nil)
                     .where(due_at: day_start..day_start.end_of_day)
                     .where(attendance: [nil, ''])
      # item 308 (01/10): consulta SEM paciente vinculado não some mais em silêncio —
      # entra na lista de "puladas" com o motivo, para a equipe completar o cadastro
      # quem já confirmou — ou disse que NÃO vai (a equipe foi avisada) — não recebe as réguas seguintes
      scope = scope.where(confirmed_at: nil, declined_at: nil) if self.class.days_of(regua).positive?
      scope.includes(:contact).find_each { |task| send_for(account, inbox, rcfg, regua, task, run, shadow: shadow) }
    end
    record_run(account, regua, run, now_sp, shadow: shadow)
    run
  end

  # item 320: envio manual para UM paciente (consulta de hoje em diante, não cancelada)
  def run_one(account, inbox, rcfg, regua, task_id, now_sp) # rubocop:disable Metrics/ParameterLists
    run = { 'sent' => [], 'skipped' => [] }
    task = account.tasks.where(task_type: 'consulta', canceled_at: nil, archived_at: nil)
                  .where(due_at: now_sp.beginning_of_day..).find_by(id: task_id)
    return run if task.nil?

    send_for(account, inbox, rcfg, regua, task, run, force: true)
    record_manual(account, regua, run, task.id, now_sp)
    run
  end

  # force (envio manual de um paciente): passa pelo filtro de coluna/tipo e pela marca de "já recebeu"
  def send_for(account, inbox, rcfg, regua, task, run, shadow: false, force: false) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
    # item 319: agendamento com telefone e sem cadastro → acha ou cria o paciente
    # (em sombra só procura; nada é criado)
    contact = task.contact || Crm::AppointmentOrigin.ensure_contact(account: account, task: task, create: !shadow)
    blocked = skip_reason(rcfg, regua, task, contact, force: force)
    return skip(run, task, blocked) if blocked

    marks = (contact.additional_attributes || {}).dig('cevico_appt_reminders', task.id.to_s) || {}
    return if reminder_spent?(marks, regua, task) && !force

    # paciente de parceiro (já liberado no skip_reason) sai pela caixa e modelo do bloco Oftalmofácil
    partner = partner_patient?(task, contact)
    if partner
      inbox = account.inboxes.find_by(id: rcfg.dig('partner', 'inbox_id'))
      return skip(run, task, 'Oftalmofácil: caixa não encontrada') if inbox.nil? && !shadow
    end
    template = partner ? partner_template(rcfg) : template_for(rcfg, regua, task)

    # item 310/314: o lembrete sai pela caixa em que o paciente JÁ conversa,
    # com o modelo escolhido PARA AQUELA CAIXA no card — por isso a falta de
    # modelo só é decidida DEPOIS do roteamento (varredura 03/10)
    inbox, template = inbox_and_template_for(account, rcfg, contact, task, inbox => template) unless partner
    return skip(run, task, partner ? 'Oftalmofácil: sem modelo' : "sem modelo para #{unit_label(task)}") if template.nil? && !shadow

    if shadow
      run['sent'] << entry_for(task, contact, template: template&.dig('template_params', 'name'), partner: partner, inbox: inbox)
      return
    end

    # marca ANTES de enviar, dentro da trava (como o reforço): duas rodadas em
    # paralelo, ou a marca falhando depois do envio, não mandam duas vezes
    return unless claim_reminder!(contact, task, regua, inbox: inbox, force: force)

    source = TemplateSource.new(account, inbox, nil,
                                personalized_params(template['template_params'], task, rcfg, template['message_preview']),
                                template['message_preview'].presence,
                                "Lembrete de consulta (#{regua.upcase})")
    conversation = Crm::SendTemplateService.new(source: source, contact: contact).perform
    if conversation.nil?
      release_reminder!(contact, task, regua)
      return skip(run, task, 'envio não saiu (contato/caixa)')
    end

    # item 300: paciente do Oftalmofácil ganha o card no funil DELE (nunca no da CEVICO)
    Crm::PartnerFunnel.place!(account, contact, :booked) if partner
    run['sent'] << entry_for(task, contact, template: template.dig('template_params', 'name'), partner: partner, inbox: inbox)
  rescue StandardError => e
    Rails.logger.error "[CEVICO lembretes] task #{task.id}: #{e.message}"
    skip(run, task, "erro: #{e.message.truncate(60)}")
  end

  # por que esta consulta NÃO recebe a régua (nil = pode receber)
  def skip_reason(rcfg, regua, task, contact, force: false) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    # com telefone e ainda sem paciente: em sombra o cadastro não é criado; ao vivo o número não deu para entender
    return (task.phone.present? ? 'telefone sem cadastro de paciente' : 'sem telefone') if contact.nil?
    return 'sem telefone' if contact.phone_number.blank?

    # 🚧 item 231 (cerca dos parceiros): consulta/exame de parceiro do hub só recebe
    # o lembrete quando o bloco "Pacientes do Oftalmofácil" deste lembrete está ligado
    if partner_patient?(task, contact) && !partner_enabled?(rcfg)
      Crm::PartnerGuard.block!("lembrete #{regua} (agendamento #{task.id})", contact: contact)
      return 'paciente de parceiro (cerca)'
    end
    return nil if force # envio manual: a equipe escolheu este paciente (coluna e tipo não barram)

    # item 312: só quem está nas colunas escolhidas do CRM (paciente de parceiro tem o bloco dele)
    by_stage = partner_patient?(task, contact) ? nil : stage_skip_reason(rcfg, contact)
    return by_stage if by_stage

    allowed = Array(rcfg['modalities']).compact_blank
    return nil if allowed.empty? || task.modality.blank? # sem filtro = todas as modalidades

    allowed.include?(task.modality) ? nil : "modalidade #{task.modality}"
  end

  # 🗂️ item 312 (02/10, "preciso poder escolher a coluna em que isso será
  # enviado"): com colunas marcadas no lembrete, só recebe quem tem o card numa
  # delas. Nenhuma marcada = todas (como era). O motivo aparece nas "puladas".
  def stage_skip_reason(rcfg, contact) # rubocop:disable Metrics/CyclomaticComplexity
    wanted = Array(rcfg['stage_ids']).map(&:to_i)
    return nil if wanted.empty?

    cards = Crm::Contact.where(contact_id: contact.id).includes(:stage).to_a
    return 'sem card no CRM' if cards.empty?
    return nil if cards.any? { |card| wanted.include?(card.stage_id) }

    "card na coluna #{cards.first.stage&.name || '?'}"
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

  # ── caixa certa para o paciente (item 310, 02/10) ─────────────────────
  # Pedido dele: "a mensagem modelo será enviada através da caixa de entrada
  # em que a conversa já existe" (Google ou Instagram). Entre a caixa padrão
  # do lembrete e as caixas marcadas em "também envia por", vale a da conversa
  # MAIS RECENTE do paciente. Sem conversa em nenhuma delas, sai pela padrão.
  def routed_inbox(account, rcfg, contact, default_inbox)
    ids = ([default_inbox&.id] + Array(rcfg['inbox_ids']).map(&:to_i)).compact.uniq
    return default_inbox if ids.size < 2

    inbox_id = patient_inbox_id(account.conversations.where(contact_id: contact.id, inbox_id: ids))
    (inbox_id && account.inboxes.find_by(id: inbox_id)) || default_inbox
  end

  # a caixa em que o PACIENTE escreveu por último — mensagem automática
  # (campanha, lembrete antigo) não "puxa" a caixa (varredura 03/10); sem
  # mensagem dele, vale a última atividade
  def patient_inbox_id(convs)
    last_incoming = Message.where(conversation_id: convs.select(:id), message_type: :incoming)
                           .joins(:conversation).unscope(:order).group('conversations.inbox_id').maximum('messages.created_at')
    last_incoming.max_by { |_inbox_id, at| at }&.first ||
      convs.order(Arel.sql('last_activity_at DESC NULLS LAST, id DESC')).pick(:inbox_id)
  end

  # Item 314 (02/10; "quero ambientes mais separados para cada caixa de
  # entrada… selecionar exatamente a mensagem modelo correta daquela caixa"):
  # cada caixa marcada tem os SEUS modelos (by_inbox.<id>.units /
  # template_params), escolhidos da lista daquele número. Caixa da conversa
  # sem modelo para a unidade da consulta → sai pela caixa padrão, com o
  # modelo padrão (nada de procurar "nome igual" na outra caixa).
  # chosen = { caixa padrão => modelo padrão }
  def inbox_and_template_for(account, rcfg, contact, task, chosen)
    default_inbox, template = chosen.first
    routed = routed_inbox(account, rcfg, contact, default_inbox)
    return [default_inbox, template] if routed.nil? || routed.id == default_inbox&.id

    own = template_for(inbox_config(rcfg, routed), nil, task)
    own ? [routed, own] : [default_inbox, template]
  end

  # A marca vale para a consulta COMO ESTAVA quando o lembrete saiu: consulta
  # remarcada (outro dia/hora) recebe o lembrete de novo (varredura 03/10). Marca
  # antiga sem a hora guardada (anterior ao item 288) continua valendo como gasta.
  def reminder_spent?(marks, regua, task)
    return false if marks[regua].blank?

    stored = marks[Crm::AppointmentReminderFollowup.due_key(regua)]
    return true if stored.blank?

    Time.zone.parse(stored.to_s).to_i == task.due_at.to_i
  rescue ArgumentError
    true
  end

  def inbox_config(rcfg, inbox)
    cfg = (rcfg['by_inbox'] || {})[inbox.id.to_s]
    cfg.is_a?(Hash) ? cfg : {}
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

  # item 319 ("devo deixar sem nenhum preenchimento, para que pegue os contatos
  # da agenda, correto?"): variável deixada EM BRANCO no card ia vazia para a
  # Meta, que recusa o modelo. Agora o branco vale o dado da Agenda, na ordem
  # dos modelos de confirmação: {{1}} nome, {{2}} data, {{3}} hora, {{4}} valor.
  BLANK_VARS = { '1' => '{{nome}}', '2' => '{{data}}', '3' => '{{hora}}', '4' => '{{valor}}' }.freeze

  def fill_blank_vars!(params, preview) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    tokens = preview.to_s.scan(/\{\{\s*(\d+)\s*\}\}/).flatten.uniq
    return if tokens.empty? && params.dig('processed_params', 'body').blank?

    body = ((params['processed_params'] ||= {})['body'] ||= {})
    (tokens | body.keys.map(&:to_s)).each do |token|
      body[token] = BLANK_VARS[token] if body[token].to_s.strip.empty? && BLANK_VARS.key?(token)
    end
  end

  # {{hora}}/{{unidade}}/{{data}}/{{nome}}/{{valor}} nos VALORES das variáveis viram o dado da consulta
  def personalized_params(template_params, task, rcfg = {}, preview = nil)
    params = template_params.deep_dup
    fill_blank_vars!(params, preview)
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
    task.title.to_s.sub(/\A(Consulta|Exame|Retorno|Pós-operatório|Teleconsulta):\s*/i, '').delete('✅').strip.presence ||
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
  def entry_for(task, contact, template: nil, partner: false, inbox: nil)
    at = task.due_at&.in_time_zone(TZ)
    { 'task_id' => task.id, 'name' => patient_name(task), 'phone_tail' => contact.phone_number.to_s.last(4),
      'when' => at&.strftime('%d/%m %H:%M'), 'unit' => unit_label(task), 'template' => template, 'contact_id' => contact.id,
      'inbox' => inbox&.name, # item 310: por qual caixa saiu / sairia
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
      dates = self.class.target_dates(regua, rcfg, now_sp).map(&:iso8601)
      state[regua] = {
        'last_run_at' => now_sp.iso8601, 'mode' => shadow ? 'shadow' : 'live', 'dates' => dates,
        'sent' => kept_sent(run, state[regua], dates, now_sp, shadow: shadow).first(LIST_CAP),
        'skipped' => run['skipped'].first(LIST_CAP)
      }
      settings.update!(agenda_config: agenda.merge(STATE_KEY => state))
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO lembretes] registro da rodada: #{e.message}"
  end

  # item 320: o envio manual de UM paciente só mexe na linha dele — sai das
  # puladas e entra nas enviadas (ou troca o motivo); o resto da lista fica
  def record_manual(account, regua, run, task_id, now_sp) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    settings.with_lock do
      agenda = settings.agenda_config || {}
      state = agenda[STATE_KEY] || {}
      prev = state[regua] || { 'mode' => 'live', 'dates' => [] }
      others = ->(list) { Array(list).reject { |entry| entry['task_id'] == task_id } }
      state[regua] = prev.merge(
        'last_manual_at' => now_sp.iso8601,
        'sent' => (others.call(prev['sent']) + run['sent'].map { |e| e.merge('manual' => true) }).first(LIST_CAP),
        'skipped' => (others.call(prev['skipped']) + run['skipped']).first(LIST_CAP)
      )
      settings.update!(agenda_config: agenda.merge(STATE_KEY => state))
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO lembretes] registro do envio manual: #{e.message}"
  end

  # o cron roda 4x por hora, na hora do lembrete e na seguinte: nas rodadas
  # depois da primeira todo mundo já tem marca e "enviadas" viria vazio (em
  # 03/10 ele viu "0 enviada(s)" às 11:45 com os envios feitos às 10h). A lista
  # do DIA vai somando: quem recebeu numa rodada continua nela (item 319).
  def kept_sent(run, previous, dates, now_sp, shadow:) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    previous ||= {}
    same_round = previous['dates'] == dates && previous['mode'] == (shadow ? 'shadow' : 'live') &&
                 same_day?(previous['last_run_at'], now_sp)
    return run['sent'] unless same_round
    return run['sent'] if shadow && run['sent'].any? # sombra lista todos de novo a cada rodada

    (Array(previous['sent']) + run['sent']).uniq { |entry| entry['task_id'] }
  end

  def same_day?(iso, now_sp)
    at = Time.zone.parse(iso.to_s)&.in_time_zone(TZ)
    at.present? && at.to_date == now_sp.to_date
  rescue ArgumentError
    false
  end

  # grava a marca dentro da trava ANTES do envio; false = outra rodada já pegou
  # esta consulta. Consulta remarcada = ciclo novo: as marcas antigas (réguas,
  # reforços, confirmou/recusou) saem para a nova data receber tudo de novo.
  def claim_reminder!(contact, task, regua, inbox: nil, force: false)
    claimed = false
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      marks = attrs['cevico_appt_reminders'] || {}
      entry = marks[task.id.to_s] || {}
      next attrs if reminder_spent?(entry, regua, task) && !force

      claimed = true
      entry = {} if entry[regua].present? # marca antiga de outra data/hora
      attrs.merge('cevico_appt_reminders' => prune_marks(marks.merge(task.id.to_s => stamped(entry, regua, task, inbox))))
    end
    claimed
  end

  def stamped(entry, regua, task, inbox)
    entry.merge(regua => Time.current.iso8601,
                Crm::AppointmentReminderFollowup.inbox_key(regua) => inbox&.id, # item 310: o reforço sai pela MESMA caixa
                Crm::AppointmentReminderFollowup.due_key(regua) => task.due_at&.iso8601).compact # item 288: remarcou = não é a mesma
  end

  # poda: marcas de consultas antigas não servem pra mais nada (só as datas
  # entram na conta — a marca também guarda o id da caixa, item 310)
  def prune_marks(marks)
    return marks unless marks.size > MAX_MARK_ENTRIES

    marks.sort_by { |_id, e| e.values.grep(String).max.to_s }.last(MAX_MARK_ENTRIES).to_h
  end

  def release_reminder!(contact, task, regua)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      marks = attrs['cevico_appt_reminders'] || {}
      entry = (marks[task.id.to_s] || {}).except(regua, Crm::AppointmentReminderFollowup.due_key(regua),
                                                 Crm::AppointmentReminderFollowup.inbox_key(regua))
      attrs.merge('cevico_appt_reminders' => marks.merge(task.id.to_s => entry))
    end
  end
end
