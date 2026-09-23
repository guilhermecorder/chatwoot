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
  KINDS = %w[agendada reagendada cancelada].freeze
  # quem marcou: rastro que o Secretário/Atendente deixa na descrição
  IA_MARKS = /pela IA|pelo Atendente|Atendente de Agendamento|Atendente P[oó]s|Secret[aá]rio da Agenda|Agente de Liga/i
  TZ = Crm::AgendaSlots::TZ

  # GET /crm/appointments/feed?preset=today|last7|month|custom&from&to&mode=registradas|consultas&kind&unit&inbox_id&q
  def feed # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    since, until_at = standard_period_range || custom_period_range
    mode = params[:mode] == 'consultas' ? 'consultas' : 'registradas'
    # 🔪 item 208 (23/09): chavinha Consultas | Cirurgias, como na Agenda —
    # mesmo painel, outro trilho (task_type 'cirurgia'); sem valores, aberto ao time
    track = params[:track] == 'cirurgias' ? 'cirurgia' : 'consulta'
    tasks = base_scope(since, until_at, mode, track).includes(:contact, :assignee, :creator).limit(LIMIT).to_a
    rows = build_rows(tasks)
    rows = rows.select { |r| r[:kind] == params[:kind] } if KINDS.include?(params[:kind].to_s)
    rows = rows.select { |r| r[:unit] == params[:unit] } if params[:unit].present?
    rows = rows.select { |r| r.dig(:conversation, :inbox_id) == params[:inbox_id].to_i } if params[:inbox_id].present?
    rows = filter_query(rows, params[:q])

    render json: {
      mode: mode, track: track == 'cirurgia' ? 'cirurgias' : 'consultas', since: since, until: until_at, rows: rows, counts: counts(rows),
      booking: booking_json
    }
  end

  private

  # registradas = ACONTECEU no período (marcou/remarcou/cancelou);
  # consultas = a consulta É no período (o dia dela)
  def base_scope(since, until_at, mode, track = 'consulta')
    # tarefas de REVISÃO do Secretário ("⚠️ Confirmar consulta…", sem data) não
    # são consultas marcadas: ficam em Tarefas, fora deste painel
    scope = Current.account.tasks.where(task_type: track, archived_at: nil).where.not(due_at: nil)
                   .where("title NOT LIKE '⚠️%'")
    return scope.where(due_at: since..until_at).order(:due_at) if mode == 'consultas'

    scope.where('(tasks.created_at BETWEEN :s AND :u) OR (tasks.canceled_at BETWEEN :s AND :u) ' \
                'OR (tasks.rescheduled_count > 0 AND tasks.updated_at BETWEEN :s AND :u)', s: since, u: until_at)
         .order(updated_at: :desc)
  end

  def build_rows(tasks) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    conversations = conversations_for(tasks)
    cards = cards_for(tasks)
    tasks.map do |t|
      contact = t.contact
      conversation = conversations[t.id]
      {
        id: t.id,
        kind: kind_of(t),
        event_at: event_at(t),
        due_at: t.due_at,
        unit: t.unit,
        unit_label: Crm::AgendaSlots::UNIT_LABELS[t.unit] || t.unit,
        doctor: t.doctor,
        procedure: t.procedure,
        name: t.title.to_s.sub(/\A(Consulta|Cirurgia):\s*/i, '').strip.presence || contact&.name || 'Paciente',
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
  end

  def kind_of(task)
    return 'cancelada' if task.canceled_at.present?
    return 'reagendada' if task.rescheduled_count.to_i.positive?

    'agendada'
  end

  def event_at(task)
    return task.canceled_at if task.canceled_at.present?
    return task.updated_at if task.rescheduled_count.to_i.positive?

    task.created_at
  end

  # a conversa de onde a consulta saiu ("Conversa #123" na descrição; vale a
  # ÚLTIMA citada = reagendamento mais recente); sem rastro, a conversa mais
  # recente do paciente
  def conversations_for(tasks) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    wanted = {}
    tasks.each do |t|
      ids = t.description.to_s.scan(/Conversa #(\d+)/).flatten
      wanted[t.id] = ids.last.to_i if ids.any?
    end
    by_display = Current.account.conversations.where(display_id: wanted.values.uniq).includes(:inbox).index_by(&:display_id)
    fallback_ids = tasks.reject { |t| by_display[wanted[t.id]] }.filter_map(&:contact_id).uniq
    latest = Current.account.conversations.where(contact_id: fallback_ids).includes(:inbox)
                    .order(last_activity_at: :desc).group_by(&:contact_id).transform_values(&:first)
    tasks.to_h { |t| [t.id, by_display[wanted[t.id]] || latest[t.contact_id]] }
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

  def counts(rows)
    {
      total: rows.size,
      agendada: rows.count { |r| r[:kind] == 'agendada' },
      reagendada: rows.count { |r| r[:kind] == 'reagendada' },
      cancelada: rows.count { |r| r[:kind] == 'cancelada' },
      ia: rows.count { |r| r[:source] == 'ia' },
      equipe: rows.count { |r| r[:source] == 'equipe' }
    }
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
