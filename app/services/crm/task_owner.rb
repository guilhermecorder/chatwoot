# Responsável automático das tarefas (pedido 20/07): cada atendente cuida
# de algumas colunas do CRM. Tarefa criada por robô (Secretário, automações,
# Atendente IA) nasce NO NOME de quem cuida da coluna onde o paciente está —
# o aviso dourado do Meu Painel chega para a pessoa certa, não para ninguém.
#
# Ordem de decisão:
#   0. RETORNO com a "Equipe dos retornos" configurada → sem responsável
#      individual (item 343, abaixo);
#   1. coluna atual do paciente no CRM → settings.task_owner_id da coluna;
#   2. sem coluna/da coluna sem dono → responsáveis da conferência
#      (agenda_config.attendance_owners: consulta/cirurgia);
#   3. nada configurado → sem responsável (como era antes).
#
# 🔁 ITEM 343 (13/10) "Retornos para a equipe dos retornos": a Vaneide
# reclamou que "vários pacientes de retorno estão sendo atribuídos a mim".
# Decisão dele: retorno é da Natália e da Elizangela e "as duas veem tudo" —
# ninguém é dono sozinho; quem pegar primeiro assume. A equipe é escolhida
# pelo admin na Agenda (Configurações → Conferência do dia → Equipe dos
# retornos) e fica em agenda_config['retorno_team_user_ids'] (sem migration).
# Sem equipe escolhida, tudo segue como era antes.
class Crm::TaskOwner
  RETORNO_TEAM_KEY = 'retorno_team_user_ids'.freeze
  # carimbo da equipe no card do quadro (tarefa de passagem de um paciente de
  # retorno): o campo `modality` já existe e não é usado nos cards
  RETORNO = 'retorno'.freeze
  # valor do seletor "Responsável pelas tarefas" dos agentes = a equipe toda
  TEAM_CHOICE = 'retorno_team'.freeze

  def self.resolve(account, contact: nil, task_type: nil, retorno: false)
    return nil if retorno && retorno_team?(account)

    user_id = stage_owner_id(account, contact) || fallback_owner_id(account, task_type)
    account.users.find_by(id: user_id) if user_id.present?
  end

  def self.stage_owner_id(account, contact)
    return nil if contact.blank?

    record = Crm::Contact.joins(:pipeline)
                         .where(crm_pipelines: { account_id: account.id }, contact_id: contact.id)
                         .order(updated_at: :desc).first
    record&.stage&.settings&.[]('task_owner_id').presence&.to_i
  end

  def self.fallback_owner_id(account, task_type)
    owners = CrmSetting.find_by(account: account)&.agenda_config&.dig('attendance_owners') || {}
    key = { 'consulta' => 'consulta_user_id', 'cirurgia' => 'cirurgia_user_id' }[task_type.to_s]
    owners[key].presence&.to_i if key
  end

  # 🔁 343: a equipe dos retornos (só quem ainda é da conta)
  def self.retorno_team_ids(account)
    ids = Array(CrmSetting.find_by(account: account)&.agenda_config&.dig(RETORNO_TEAM_KEY)).map(&:to_i).select(&:positive?)
    return [] if ids.empty?

    account.users.where(id: ids).pluck(:id)
  end

  def self.retorno_team?(account)
    retorno_team_ids(account).any?
  end

  def self.retorno_team_member?(account, user)
    user.present? && retorno_team_ids(account).include?(user.id)
  end

  # É retorno? Aceita a Task ou um hash de atributos. Vale o tipo escolhido
  # (modality 'retorno' — também é o carimbo da equipe nos cards) ou, em
  # consulta sem tipo / avaliação, o procedimento escrito "Retorno" (o que a
  # IA anota) — "retorno pós-op" é pós-operatório, não entra.
  def self.retorno?(task_or_attrs)
    return false if task_or_attrs.blank?

    modality = attr_of(task_or_attrs, :modality).to_s
    return true if modality == RETORNO
    return false unless attr_of(task_or_attrs, :task_type).to_s == 'consulta' && ['', 'avaliacao'].include?(modality)

    text = attr_of(task_or_attrs, :procedure).to_s
    text.match?(/\bretorno\b/i) && !text.match?(/p[oó]s.?op/i)
  end

  # o paciente está em RETORNO? = a próxima consulta dele (de hoje em diante,
  # não cancelada, ainda aberta) é um retorno
  def self.patient_retorno?(account, contact)
    return false if contact.blank?

    next_visit = Task.for_patient(account, contact)
                     .where(task_type: 'consulta', canceled_at: nil, status: %i[todo doing])
                     .where('due_at >= ?', Time.current.in_time_zone('America/Sao_Paulo').beginning_of_day)
                     .order(:due_at).first
    retorno?(next_visit)
  end

  # agendamento NOVO de retorno (Agenda, IA, Oftalmofácil…): sem dono
  # individual quando a equipe está configurada — a Agenda já mostra
  # consulta para a equipe toda (Task.visible_to). Chamado pelo Task antes
  # de criar (depois de descobrir se é retorno pelo histórico do paciente).
  def self.apply_retorno_team!(task)
    return unless task.appointment? && retorno?(task) && retorno_team?(task.account)

    task.assignee = nil
  end

  def self.attr_of(source, key)
    return source.public_send(key) if source.respond_to?(key)

    source[key] || source[key.to_s] if source.respond_to?(:[])
  end
  private_class_method :attr_of
end
