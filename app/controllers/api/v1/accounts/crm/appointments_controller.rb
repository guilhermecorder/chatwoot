# 📅 PAINEL DE AGENDAMENTOS (item 200, 22/09): "um ambiente em que os
# agendamentos são registrados — o trabalho das meninas será de monitoramento".
# Lista, no período, cada consulta MARCADA, REMARCADA ou CANCELADA (pelo robô
# do N8N via Secretário da Agenda, pelo Atendente interno ou pela equipe), com
# a caixa de entrada da conversa, as etiquetas do paciente, nome e telefone,
# e os atalhos: abrir a conversa, Espaço do Paciente e ligar.
# Fonte: tasks do tipo 'consulta' (a mesma Agenda). Aberto ao time inteiro.
class Api::V1::Accounts::Crm::AppointmentsController < Api::V1::Accounts::BaseController
  include Crm::ResolvesPeriod

  LIMIT = 500
  # 📅 item 217 (23/09): o que CONTA como o quê
  #   agendada     = consulta NOVA criada no período (robô ou equipe)
  #   lancada      = consulta que já estava marcada fora do sistema e foi só
  #                  lançada na Agenda (booking_kind 'registro') — não é agendamento
  #   reagendada   = mudou de dia/hora
  #   confirmada   = paciente respondeu SIM ao lembrete da véspera
  #   nao_confirmou= paciente respondeu NÃO ao lembrete (consulta segue na Agenda)
  #   cancelada    = desmarcada
  # No modo "registradas" cada ACONTECIMENTO do período vira uma linha (a
  # mesma consulta pode ter sido marcada e confirmada no período).
  KINDS = %w[agendada lancada reagendada confirmada nao_confirmou cancelada].freeze
  EVENT_GAP = 5.seconds
  # quem marcou: rastro que o Secretário/Atendente deixa na descrição
  IA_MARKS = /pela IA|pelo Atendente|Atendente de Agendamento|Atendente P[oó]s|Secret[aá]rio da Agenda|Agente de Liga/i
  TZ = Crm::AgendaSlots::TZ

  # 📅 item 210 (23/09): os 4 TRILHOS da Agenda no mesmo painel —
  # consultas | teleconsultas | exames | cirurgias (o mesmo seletor da Agenda).
  # cirurgias = task_type 'cirurgia'; os outros três são task_type 'consulta'
  # separados pela modality ('teleconsulta' | 'exames' | o resto = consultas).
  TRACKS = %w[consultas teleconsultas exames cirurgias].freeze

  # GET /crm/appointments/feed?preset=today|last7|month|custom&from&to&mode=registradas|consultas&track&kind&unit&inbox_id&q
  def feed # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    since, until_at = standard_period_range || custom_period_range
    mode = params[:mode] == 'consultas' ? 'consultas' : 'registradas'
    track = TRACKS.include?(params[:track].to_s) ? params[:track].to_s : 'consultas'
    tasks = base_scope(since, until_at, mode, track).includes(:contact, :assignee, :creator).limit(LIMIT).to_a
    rows = build_rows(tasks, mode, since, until_at)
    rows = rows.select { |r| r[:kind] == params[:kind] } if KINDS.include?(params[:kind].to_s)
    # 📊 item 235: unidades e caixas MÚLTIPLAS (units[]=paulista&units[]=tatuape;
    # inbox_ids[]=12&inbox_ids[]=3) — os antigos unit / inbox_id continuam valendo
    units = Array(params[:units]).map(&:to_s).compact_blank.presence || Array(params[:unit].presence).map(&:to_s)
    rows = rows.select { |r| units.include?(r[:unit].to_s) } if units.any?
    # empilhamento por caixa: contado ANTES do filtro de caixa, pra mostrar a fatia de cada uma
    by_inbox = stack_by_inbox(rows)
    inbox_ids = Array(params[:inbox_ids]).map(&:to_i).select(&:positive?).presence || Array(params[:inbox_id].presence).map(&:to_i)
    rows = rows.select { |r| inbox_ids.include?(r.dig(:conversation, :inbox_id).to_i) } if inbox_ids.any?
    rows = filter_query(rows, params[:q])

    render json: {
      mode: mode, track: track, since: since, until: until_at, rows: rows, counts: counts(rows),
      by_inbox: by_inbox, booking: booking_json
    }
  end

  private

  # registradas = ACONTECEU no período (marcou/remarcou/cancelou);
  # consultas = a consulta É no período (o dia dela)
  def base_scope(since, until_at, mode, track = 'consultas')
    # tarefas de REVISÃO do Secretário ("⚠️ Confirmar consulta…", sem data) não
    # são consultas marcadas: ficam em Tarefas, fora deste painel
    scope = track_scope(track).where(archived_at: nil).where.not(due_at: nil)
                              .where("title NOT LIKE '⚠️%'")
    return scope.where(due_at: since..until_at).order(:due_at) if mode == 'consultas'

    scope.where('(tasks.created_at BETWEEN :s AND :u) OR (tasks.canceled_at BETWEEN :s AND :u) ' \
                'OR (tasks.confirmed_at BETWEEN :s AND :u) OR (tasks.declined_at BETWEEN :s AND :u) ' \
                'OR (tasks.rescheduled_count > 0 AND tasks.updated_at BETWEEN :s AND :u)', s: since, u: until_at)
         .order(updated_at: :desc)
  end

  # o trilho em SQL (a mesma regra do kindOf do cevicoAgenda.js)
  def track_scope(track)
    tasks = Current.account.tasks
    case track
    when 'cirurgias' then tasks.where(task_type: 'cirurgia')
    when 'teleconsultas' then tasks.where(task_type: 'consulta', modality: 'teleconsulta')
    when 'exames' then tasks.where(task_type: 'consulta', modality: 'exames')
    else tasks.where(task_type: 'consulta').where("modality IS NULL OR modality NOT IN ('teleconsulta', 'exames')")
    end
  end

  def build_rows(tasks, mode, since, until_at) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    conversations = conversations_for(tasks)
    cards = cards_for(tasks)
    rows = tasks.flat_map do |t|
      events = mode == 'consultas' ? [[kind_of(t), event_at(t)]] : events_of(t, since, until_at)
      events.map { |kind, at| row_for(t, kind, at, conversations[t.id], cards) }
    end
    mode == 'consultas' ? rows : rows.sort_by { |r| r[:event_at] }.reverse
  end

  # os acontecimentos DESTA consulta dentro do período (modo registradas)
  def events_of(task, since, until_at) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    range = since..until_at
    ev = []
    ev << [task.registered_only? ? 'lancada' : 'agendada', task.created_at] if range.cover?(task.created_at)
    ev << ['confirmada', task.confirmed_at] if task.confirmed_at && range.cover?(task.confirmed_at)
    ev << ['nao_confirmou', task.declined_at] if task.declined_at && range.cover?(task.declined_at)
    ev << ['cancelada', task.canceled_at] if task.canceled_at && range.cover?(task.canceled_at)
    # reagendamento não tem carimbo próprio: vale o updated_at, desde que não
    # seja só o rastro de outro acontecimento (criação/confirmação/cancelamento)
    if task.rescheduled_count.to_i.positive? && range.cover?(task.updated_at) &&
       [task.created_at, task.confirmed_at, task.declined_at, task.canceled_at].compact.none? { |t| (task.updated_at - t).abs < EVENT_GAP }
      ev << ['reagendada', task.updated_at]
    end
    ev.presence || [[kind_of(task), event_at(task)]]
  end

  def row_for(t, kind, at, conversation, cards) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    contact = t.contact
    {
        id: "#{t.id}-#{kind}",
        task_id: t.id,
        booking_kind: t.booking_kind,
        confirmed_at: t.confirmed_at,
        declined_at: t.declined_at,
        kind: kind,
        event_at: at,
        due_at: t.due_at,
        unit: t.unit,
        unit_label: Crm::AgendaSlots::UNIT_LABELS[t.unit] || t.unit,
        doctor: t.doctor,
        procedure: t.procedure,
        modality: t.modality,
        track: track_of(t),
        name: t.title.to_s.sub(/\A(Consulta|Teleconsulta|Exame|Cirurgia):\s*/i, '').strip.presence || contact&.name || 'Paciente',
        phone: t.phone.presence || contact&.phone_number,
        source: t.description.to_s.match?(IA_MARKS) ? 'ia' : 'equipe',
        rescheduled_count: t.rescheduled_count,
        canceled_at: t.canceled_at,
        status: t.status,
        attendance: t.attendance,
        assignee: t.assignee ? { id: t.assignee.id, name: t.assignee.name } : nil,
        creator: t.creator ? { id: t.creator.id, name: t.creator.name } : nil,
        contact: contact && {
          id: contact.id, name: contact.name, phone: contact.phone_number, thumbnail: contact.avatar_url,
          labels: contact.label_list.map(&:to_s)
        },
        conversation: conversation && {
          display_id: conversation.display_id, inbox_id: conversation.inbox_id,
          inbox_name: conversation.inbox&.name, labels: conversation.cached_label_list_array
        },
        card: cards[t.contact_id]
    }
  end

  def track_of(task)
    return 'cirurgias' if task.task_type == 'cirurgia'
    return 'teleconsultas' if task.modality == 'teleconsulta'
    return 'exames' if task.modality == 'exames'

    'consultas'
  end

  # estado atual da consulta (modo "consultas do período": uma linha por consulta)
  def kind_of(task)
    return 'cancelada' if task.canceled_at.present?
    return 'reagendada' if task.rescheduled_count.to_i.positive?
    return 'nao_confirmou' if task.declined_at.present?
    return 'confirmada' if task.confirmed_at.present?
    return 'lancada' if task.registered_only?

    'agendada'
  end

  def event_at(task)
    return task.canceled_at if task.canceled_at.present?
    return task.updated_at if task.rescheduled_count.to_i.positive?
    return task.declined_at if task.declined_at.present?
    return task.confirmed_at if task.confirmed_at.present?

    task.created_at
  end

  # a conversa de onde a consulta saiu — regra compartilhada com o Meu Painel
  # (item 238: Crm::TaskConversations)
  def conversations_for(tasks)
    Crm::TaskConversations.for(Current.account, tasks)
  end

  def cards_for(tasks)
    Crm::Contact.where(contact_id: tasks.filter_map(&:contact_id).uniq).includes(:stage, :pipeline)
                .order(:updated_at).each_with_object({}) do |card, acc|
      acc[card.contact_id] = { stage: card.stage&.name, stage_color: card.stage&.color, pipeline: card.pipeline&.name,
                               stage_id: card.stage_id }
    end
  end

  def filter_query(rows, query)
    q = query.to_s.strip.downcase
    return rows if q.blank?

    digits = q.gsub(/\D/, '')
    rows.select do |r|
      I18n.transliterate(r[:name].to_s).downcase.include?(I18n.transliterate(q)) ||
        (digits.length >= 4 && r[:phone].to_s.gsub(/\D/, '').include?(digits))
    end
  end

  # robô × equipe só entre o que foi MARCADO/REMARCADO/CANCELADO (confirmação
  # é do paciente; lançamento é sempre da equipe)
  BOOKING_KINDS_FOR_SOURCE = %w[agendada reagendada cancelada].freeze

  # item 235: quantos registros vieram de cada caixa (ordem: maior primeiro)
  def stack_by_inbox(rows)
    rows.group_by { |r| [r.dig(:conversation, :inbox_id), r.dig(:conversation, :inbox_name)] }
        .map { |(id, name), list| { inbox_id: id, name: name.presence || 'sem conversa', count: list.size,
                                    ia: list.count { |r| r[:source] == 'ia' }, equipe: list.count { |r| r[:source] == 'equipe' } } }
        .sort_by { |h| -h[:count] }
  end

  def counts(rows)
    booked = rows.select { |r| BOOKING_KINDS_FOR_SOURCE.include?(r[:kind]) }
    KINDS.to_h { |k| [k.to_sym, rows.count { |r| r[:kind] == k }] }.merge(
      total: rows.size,
      ia: booked.count { |r| r[:source] == 'ia' },
      equipe: booked.count { |r| r[:source] == 'equipe' }
    )
  end

  # configuração dos efeitos (etiquetas + colunas) + colunas disponíveis p/ o admin escolher
  def booking_json
    cfg = Crm::BookingSideEffects.config(Current.account)
    stages = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: Current.account.id })
                       .order('crm_pipelines.position, crm_stages.position')
                       .map { |st| { id: st.id, name: st.name, pipeline: st.pipeline.name } }
    cfg.merge('effective_stage_id' => Crm::BookingSideEffects.booking_stage_id(Current.account),
              'stages' => stages, 'can_edit' => Current.account_user.administrator?)
  end
end
