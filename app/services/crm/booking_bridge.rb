# 🌉 item 285 (29/09): a PONTE entre os dois números do painel de Agendamentos —
# "4 entraram em Agendamento de Consulta, ok; mas teve 13 marcadas. O que é essa
# diferença?". Filosofia dele: revelar os dados pelas conexões (de onde veio,
# como se ramifica, pra onde vai).
#   coluna  = pacientes cujo card ENTROU na coluna de agendamento no período
#   agenda  = consultas NOVAS criadas na Agenda no período (as "marcadas")
# Cada marcada cai em UM ramo (por que o paciente dela não está entre os que
# entraram na coluna) e cada entrada na coluna também (tem ou não consulta).
class Crm::BookingBridge
  AGENDA_BRANCHES = {
    'both' => ['entraram na coluna no período', 'o card chegou na coluna e a consulta foi marcada — os dois números contam este paciente'],
    'entered_before' => ['já tinham entrado na coluna antes', 'o card passou pela coluna antes deste período; a consulta só foi marcada agora'],
    'entered_after' => ['entraram na coluna depois', 'a consulta foi marcada no período e o card só chegou na coluna depois'],
    'other_stage' => ['com card em outra coluna (nunca passou pela de agendamento)',
                      'paciente que já estava mais adiante (retorno, cirurgia, pós-operatório) ou cujo card não foi movido'],
    'other_pipeline' => ['com card só em outro funil', 'paciente de outro funil (ex.: Oftalmofácil) — não passa pela coluna deste funil'],
    'no_card' => ['sem card no CRM', 'tem cadastro, mas nunca virou card no funil'],
    'no_contact' => ['sem cadastro ligado', 'foi marcada na Agenda sem ligar a um paciente do sistema']
  }.freeze
  COLUMN_BRANCHES = {
    'both' => ['com consulta marcada no período', 'o card chegou na coluna e a consulta foi marcada na Agenda'],
    'consult_before' => ['a consulta já estava marcada antes', 'a consulta na Agenda foi criada antes deste período'],
    'consult_after' => ['a consulta foi marcada depois', 'a consulta na Agenda foi criada depois deste período'],
    'no_consult' => ['sem consulta na Agenda', 'o card entrou na coluna, mas ninguém marcou a consulta na Agenda — vale conferir']
  }.freeze

  def initialize(account)
    @account = account
  end

  def call(since, until_at)
    @since = since
    @until_at = until_at
    @stage = Crm::BookingRate.stage(@account)
    return nil unless @stage

    load_data
    agenda = branches(AGENDA_BRANCHES, @tasks.group_by { |t| agenda_branch(t) }) { |t| task_person(t) }
    column = branches(COLUMN_BRANCHES, @entered.keys.group_by { |id| column_branch(id) }) { |id| entry_person(id) }
    summary(agenda, column)
  end

  private

  def load_data # rubocop:disable Metrics/AbcSize
    load_entered
    @tasks = consult_scope.bookings.where(created_at: @since..@until_at).includes(:contact).order(:created_at).to_a
    ids = (@tasks.filter_map(&:contact_id) + @entered.keys).uniq
    @cards = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }, contact_id: ids)
                         .includes(:stage, :pipeline).group_by(&:contact_id)
    @passages = passages_for(ids)
    @consults = consult_scope.where(contact_id: @entered.keys).order(:created_at).group_by(&:contact_id)
    @contacts = @account.contacts.where(id: @entered.keys).index_by(&:id)
  end

  # { contact_id => quando entrou na coluna (a 1ª vez no período) }
  def load_entered
    @entered = {}
    Crm::BookingRate.entries(@account, @since, @until_at).joins(:crm_contact).order(:entered_at)
                    .pluck('crm_contacts.contact_id', :entered_at).each { |id, at| @entered[id] ||= at }
  end

  # a mesma régua do painel: consulta de verdade (sem tele/exame, sem avisos ⚠️, sem arquivadas)
  def consult_scope
    @account.tasks.where(task_type: 'consulta', archived_at: nil).where.not(due_at: nil)
            .where("title NOT LIKE '⚠️%'")
            .where("modality IS NULL OR modality NOT IN ('teleconsulta', 'exames')")
  end

  # todas as passagens pela coluna de agendamento, em qualquer época: { contact_id => [datas] }
  def passages_for(ids)
    Crm::StageLog.where(stage_id: @stage.id, event_type: 'entered').joins(:crm_contact)
                 .where(crm_contacts: { contact_id: ids })
                 .pluck('crm_contacts.contact_id', :entered_at)
                 .group_by(&:first).transform_values { |list| list.filter_map(&:last).sort }
  end

  def agenda_branch(task) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    id = task.contact_id
    return 'no_contact' unless id
    return 'both' if @entered.key?(id)

    passed = @passages[id] || []
    return 'entered_before' if passed.any? { |at| at < @since }
    return 'entered_after' if passed.any?

    cards = @cards[id] || []
    return 'no_card' if cards.empty?

    cards.any? { |c| c.pipeline_id == @stage.pipeline_id } ? 'other_stage' : 'other_pipeline'
  end

  def column_branch(contact_id)
    consults = @consults[contact_id] || []
    return 'no_consult' if consults.empty?
    return 'both' if consults.any? { |t| (@since..@until_at).cover?(t.created_at) }

    consults.any? { |t| t.created_at < @since } ? 'consult_before' : 'consult_after'
  end

  def branches(labels, groups, &)
    labels.filter_map do |key, (label, hint)|
      list = groups[key]
      next if list.blank?

      people = list.map(&)
      { key: key, label: label, hint: hint, count: list.size, patients: people.filter_map { |p| p[:contact_id] }.uniq.size,
        stages: stage_split(people), people: people }
    end
  end

  # pra onde esses pacientes estão HOJE no CRM (a ramificação seguinte)
  def stage_split(people) # rubocop:disable Metrics/CyclomaticComplexity
    people.uniq { |p| p[:contact_id] || p[:id] }.group_by { |p| [p[:stage_now], p[:stage_now_color]] }
          .map { |(name, color), list| { name: name || 'sem card', color: color || '#94a3b8', count: list.size } }
          .sort_by { |s| -s[:count] }
  end

  def task_person(task) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    card = main_card(task.contact_id)
    passed = (@passages[task.contact_id] || []).last
    { id: task.id, task_id: task.id, contact_id: task.contact_id,
      name: task.contact&.name.presence || task.title.to_s.sub(/\A(Consulta|Teleconsulta|Exame|Cirurgia):\s*/i, '').strip,
      phone: task.phone.presence || task.contact&.phone_number, when: task.created_at, due_at: task.due_at,
      source: Crm::BookingSource.of(task), stage_now: card&.stage&.name, stage_now_color: card&.stage&.color,
      pipeline: card&.pipeline&.name, passed_at: passed }
  end

  def entry_person(contact_id) # rubocop:disable Metrics/CyclomaticComplexity
    contact = @contacts[contact_id]
    card = main_card(contact_id)
    consult = (@consults[contact_id] || []).last
    { id: contact_id, contact_id: contact_id, name: contact&.name, phone: contact&.phone_number, when: @entered[contact_id],
      stage_now: card&.stage&.name, stage_now_color: card&.stage&.color, pipeline: card&.pipeline&.name,
      consult_created_at: consult&.created_at, due_at: consult&.due_at }
  end

  # o card do funil da coluna de agendamento; sem ele, o que se mexeu por último
  def main_card(contact_id)
    cards = @cards[contact_id] || []
    cards.find { |c| c.pipeline_id == @stage.pipeline_id } || cards.max_by { |c| c.stage_moved_at || c.updated_at }
  end

  def summary(agenda, column)
    both = agenda.find { |b| b[:key] == 'both' }
    {
      stage: { id: @stage.id, name: @stage.name, color: @stage.color },
      column_total: @entered.size, agenda_total: @tasks.size,
      agenda_patients: @tasks.filter_map(&:contact_id).uniq.size + @tasks.count { |t| t.contact_id.nil? },
      both_patients: both ? both[:patients] : 0, both_consults: both ? both[:count] : 0,
      agenda: agenda, column: column
    }
  end
end
