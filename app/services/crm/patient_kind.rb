# 👥 item 271 (28/09): QUEM é o paciente de cada consulta marcada — "não podemos
# chamar tudo de agendamento" nem chamar tudo de "base". No banco real (30 dias
# até 21/09) a "base" era: 29 leads antigos (chegaram há meses e só agora
# marcaram = ainda é aquisição), 16 retornos (já tinham consultado) e 7
# pacientes de cirurgia (Oftalmofácil). Daí as 5 caixinhas:
#   novo         = chegou há até 30 dias (mesma regra do item 267 / LeadCohort)
#   lead_antigo  = chegou há mais de 30 dias e NUNCA consultou nem operou
#   retorno      = já teve consulta ANTES desta ser marcada
#   cirurgia     = já tinha cirurgia (na Agenda ou no Oftalmofácil) — pós-op/retorno de cirurgia
#   sem_cadastro = consulta sem contato ligado
module Crm::PatientKind
  module_function

  KINDS = %w[novo lead_antigo retorno cirurgia sem_cadastro].freeze
  NEW_COHORTS = %w[mesmo_dia semana mes].freeze
  LABELS = {
    'novo' => 'leads novos', 'lead_antigo' => 'leads antigos', 'retorno' => 'retornos',
    'cirurgia' => 'pacientes de cirurgia', 'sem_cadastro' => 'sem cadastro'
  }.freeze
  HINTS = {
    'novo' => 'chegaram há até 30 dias',
    'lead_antigo' => 'chegaram há mais de 30 dias e nunca tinham consultado — ainda é aquisição',
    'retorno' => 'já tinham consultado antes',
    'cirurgia' => 'já tinham cirurgia (Agenda ou Oftalmofácil)',
    'sem_cadastro' => 'consulta sem paciente ligado'
  }.freeze

  # tasks → { task_id => kind }, em 3 consultas no banco (nunca 1 por tarefa)
  def for_tasks(account, tasks) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    tasks = Array(tasks)
    ids = tasks.filter_map(&:contact_id).uniq
    return tasks.to_h { |t| [t.id, 'sem_cadastro'] } if ids.empty?

    # consultas anteriores (pela DATA da consulta) e cirurgias anteriores (pela criação)
    prior_consultas = account.tasks.where(task_type: 'consulta', contact_id: ids).where.not(due_at: nil)
                             .where("title NOT LIKE '⚠️%'").pluck(:id, :contact_id, :due_at)
    prior_cirurgias = account.tasks.where(task_type: 'cirurgia', contact_id: ids).pluck(:contact_id, :created_at)
    of_by_contact = Crm::OftalmofacilSurgery.where(account_id: account.id, contact_id: ids)
                                            .group(:contact_id).minimum(:of_created_at)
    consultas_by_contact = prior_consultas.group_by { |(_, cid, _)| cid }
    cirurgias_by_contact = prior_cirurgias.group_by(&:first)

    tasks.to_h do |t|
      kind =
        if t.contact.blank?
          'sem_cadastro'
        elsif NEW_COHORTS.include?(Crm::LeadCohort.of(t.contact, t))
          'novo'
        elsif cirurgias_by_contact[t.contact_id]&.any? { |(_, at)| at && at < t.created_at } ||
              (of_by_contact[t.contact_id].present? && of_by_contact[t.contact_id] < t.created_at)
          'cirurgia'
        elsif consultas_by_contact[t.contact_id]&.any? { |(id, _, due)| id != t.id && due && due < t.created_at }
          'retorno'
        else
          'lead_antigo'
        end
      [t.id, kind]
    end
  end

  # caixa de ORIGEM = a da PRIMEIRA conversa do paciente (por onde ele chegou)
  def origin_inbox_by_contact(account, contact_ids)
    ids = Array(contact_ids).compact.uniq
    return {} if ids.empty?

    first = Conversation.where(account_id: account.id, contact_id: ids)
                        .select('DISTINCT ON (contact_id) contact_id, inbox_id').order('contact_id, created_at ASC')
                        .to_h { |c| [c.contact_id, c.inbox_id] }
    names = account.inboxes.where(id: first.values.uniq).pluck(:id, :name).to_h
    first.transform_values { |inbox_id| { id: inbox_id, name: names[inbox_id] } }
  end
end
