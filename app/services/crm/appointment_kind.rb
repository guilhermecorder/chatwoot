# 🏷️ TIPO DO ATENDIMENTO NO CARD (item 344, 13/10 noite). O funil do
# Oftalmofácil era organizado por TIPO (Cirurgia, Exame, Consulta, Lente
# Rígida, Retornos, Intravítrea) "para as meninas se organizarem melhor" — mas
# um card só fica numa coluna, e a coluna tem que dizer a ETAPA (agendou,
# veio, operou, pós-op, retorno). Decisão do Guilherme: "Etapas + tipo no
# cartão" — as colunas viram a jornada e o TIPO vira uma etiqueta colorida no
# card + botões de filtro no topo do CRM, preenchidos SOZINHOS pela Agenda.
#
# O tipo sai do agendamento que vale para o paciente: o PRÓXIMO (não
# cancelado); sem próximo, o mais recente. Lê o tipo da Agenda (cirurgia,
# exames, retorno, pós-op) e o texto do procedimento (inclusive o tipo do hub).
module Crm::AppointmentKind
  module_function

  KINDS = {
    'consulta' => { label: 'Consulta', color: '#2563EB' },
    'exame' => { label: 'Exame', color: '#0891B2' },
    'cirurgia' => { label: 'Cirurgia', color: '#7C3AED' },
    'lente' => { label: 'Lente Rígida', color: '#DB2777' },
    'retorno' => { label: 'Retorno', color: '#16A34A' },
    'pos_op' => { label: 'Pós-op', color: '#0F766E' },
    'intravitrea' => { label: 'Intravítrea', color: '#EA580C' }
  }.freeze

  # "lente" sozinho não serve: catarata é "facectomia com LIO (lente intraocular)"
  LENTE = /lente.{0,5}rigid|rigida|adaptac.{0,10}lente|escleral/
  INTRAVITREA = /intravit|anti.?vegf/

  def fold(text)
    I18n.transliterate(text.to_s).downcase.squish
  end

  def kind_of(task, hub_type = nil) # rubocop:disable Metrics/CyclomaticComplexity
    text = fold([hub_type, task.procedure, task.title].compact.join(' '))
    return 'lente' if text.match?(LENTE)
    return 'intravitrea' if text.match?(INTRAVITREA)
    return 'cirurgia' if task.task_type == 'cirurgia'
    return 'exame' if task.modality == 'exames'
    return 'pos_op' if task.modality == 'pos_op'
    return 'retorno' if task.modality == 'retorno' || text.match?(/\bretorno/)

    'consulta'
  end

  # contact_id → { key:, label:, color:, at:, upcoming: }
  def for_contacts(account, contact_ids) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return {} if contact_ids.blank?

    tasks = account.tasks.where(contact_id: contact_ids, task_type: %w[consulta cirurgia], canceled_at: nil, archived_at: nil)
                   .where.not(due_at: nil)
                   .select(:id, :contact_id, :task_type, :modality, :procedure, :title, :due_at, :external_ref).to_a
    refs = tasks.filter_map(&:external_ref)
    hub = refs.empty? ? {} : Crm::OftalmofacilSurgery.where(account_id: account.id, item_token: refs).pluck(:item_token, :procedure_type).to_h
    today = Time.current.beginning_of_day
    tasks.group_by(&:contact_id).transform_values do |list|
      upcoming = list.select { |t| t.due_at >= today }.min_by(&:due_at)
      pick = upcoming || list.max_by(&:due_at)
      key = kind_of(pick, hub[pick.external_ref])
      KINDS[key].merge(key: key, at: pick.due_at.iso8601, upcoming: upcoming.present?)
    end
  end
end
