# 🧾 PONTA 1 (22/10, "realizada com prova"): o OftalmoFácil nunca marca a
# cirurgia como realizada — a régua `concluidas` (ativa com a data passada)
# conta como feita até cirurgia que não aconteceu. Aqui cada concluída ganha
# a PROVA que tem (a mais forte primeiro):
#   pago    → pagamento aprovado lá (PAID_AMOUNT > 0; atenção: o valor é do
#             AGENDAMENTO inteiro, os dois olhos juntos)
#   equipe  → o card do paciente está ou passou por Cirurgia Realizada,
#             Pós Operatório, Consulta Pós Op ou 2º Olho (o sync nunca põe
#             ninguém ali: quem põe é a equipe ou a Agenda de pós-op)
#   agenda  → consulta de pós-op na Agenda a partir da data da cirurgia, ou
#             a cirurgia marcada como "compareceu" na Agenda
#   nil     → "realizada sem prova"
# Só RÓTULO: nenhum valor de faturamento muda por causa disto.
class Crm::SurgeryProof
  KINDS = %w[pago equipe agenda].freeze
  LABELS = {
    'pago' => 'pagamento aprovado no OftalmoFácil',
    'equipe' => 'card em Cirurgia Realizada ou Pós-operatório',
    'agenda' => 'pós-op ou presença na Agenda',
    nil => 'sem prova'
  }.freeze
  # nomes das colunas sem acento e em minúsculas
  STAGE_PATTERN = /cirurgia realizada|pos.?operat|pos.?op|2.{0,3}olho/

  def self.label(kind)
    LABELS[kind]
  end

  def initialize(account)
    @account = account
  end

  # surgeries: as CONCLUÍDAS (Array ou relation) → { surgery.id => 'pago' | 'equipe' | 'agenda' | nil }
  def call(surgeries)
    list = surgeries.to_a
    contact_ids = list.filter_map(&:contact_id).uniq
    stage_dates = team_stage_dates(contact_ids)
    tasks = agenda_tasks(contact_ids)
    list.to_h { |s| [s.id, kind_for(s, stage_dates[s.contact_id], tasks[s.contact_id] || [])] }
  end

  # { 'pago' => n, 'equipe' => n, 'agenda' => n, 'sem_prova' => n }
  def self.tally(proofs)
    out = KINDS.index_with { 0 }.merge('sem_prova' => 0)
    proofs.each_value { |k| out[k || 'sem_prova'] += 1 }
    out
  end

  private

  def kind_for(surgery, team, tasks) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'pago' if surgery.paid_amount.to_f.positive?
    return nil if surgery.contact_id.nil? || surgery.surgery_date.nil?
    return 'equipe' if team && (team[:current] || team[:entered].any? { |d| d >= surgery.surgery_date - 1 })
    return 'agenda' if tasks.any? { |t| agenda_proof?(t, surgery) }

    nil
  end

  def agenda_proof?(task, surgery) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    day = task.due_at&.in_time_zone('America/Sao_Paulo')&.to_date
    return false if day.nil?
    return true if pos_op?(task) && day >= surgery.surgery_date

    task.attendance == 'attended' && (task.external_ref == surgery.item_token ||
      (task.task_type == 'cirurgia' && day == surgery.surgery_date))
  end

  def pos_op?(task)
    task.modality == 'pos_op' || task.task_type == 'pos_op'
  end

  # { contact_id => { current: true/false, entered: [datas em que entrou numa coluna de pós] } }
  def team_stage_dates(contact_ids) # rubocop:disable Metrics/AbcSize
    return {} if contact_ids.empty?

    stage_ids = post_stage_ids
    return {} if stage_ids.empty?

    out = Hash.new { |h, k| h[k] = { current: false, entered: [] } }
    cards = Crm::Contact.where(contact_id: contact_ids, pipeline_id: pipeline_ids).pluck(:id, :contact_id, :stage_id)
    owner = {}
    cards.each do |id, contact_id, stage_id|
      owner[id] = contact_id
      out[contact_id][:current] = true if stage_ids.include?(stage_id)
    end
    Crm::StageLog.where(crm_contact_id: owner.keys, stage_id: stage_ids).pluck(:crm_contact_id, :entered_at).each do |card_id, at|
      out[owner[card_id]][:entered] << at.in_time_zone('America/Sao_Paulo').to_date if at
    end
    out
  end

  def pipeline_ids
    @pipeline_ids ||= Crm::Pipeline.where(account_id: @account.id).pluck(:id)
  end

  def post_stage_ids
    @post_stage_ids ||= Crm::Stage.where(pipeline_id: pipeline_ids).pluck(:id, :name).filter_map do |id, name|
      id if name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.match?(STAGE_PATTERN)
    end
  end

  def agenda_tasks(contact_ids)
    return {} if contact_ids.empty?

    @account.tasks.where(contact_id: contact_ids, canceled_at: nil)
            .where("tasks.modality = 'pos_op' OR tasks.task_type = 'pos_op' OR tasks.attendance = 'attended'")
            .select(:id, :contact_id, :due_at, :modality, :task_type, :attendance, :external_ref)
            .group_by(&:contact_id)
  end
end
